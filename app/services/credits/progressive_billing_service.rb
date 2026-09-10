# frozen_string_literal: true

module Credits
  class ProgressiveBillingService < BaseService
    Result = BaseResult[:credits]

    def initialize(invoice:, apply_coupons: false)
      @invoice = invoice
      @apply_coupons = apply_coupons
      super
    end

    def call
      result.credits = []
      billed_amounts = progressive_billed_amounts

      if apply_coupons && billed_amounts.any?
        # Reconcile coupons already used on progressive invoices against the full
        # fee base, regardless of their scope. Newly applied coupons discount the
        # remaining balance after the progressive credit, in the caller's pass.
        applied_coupon_ids = Credit.active.coupon_kind
          .where(invoice_id: billed_amounts.map { |_, billed| billed.progressive_billing_invoice.id })
          .select(:applied_coupon_id)
        Credits::AppliedCouponsService.call!(invoice:, applied_coupon_ids:)
        invoice.fees.reload
      end

      billed_amounts.each do |subscription_id, progressive_billed_result|
        progressive_billing_invoice = progressive_billed_result.progressive_billing_invoice
        fees = matching_fees(subscription_id, progressive_billing_invoice)
        total_charges_amount = fees.sum(&:sub_total_excluding_taxes_amount_cents).round

        # Don't be tempted to calculate the credit amount yourself, you have to use the result from this service.
        amount_to_credit = progressive_billed_result.to_credit_amount

        if amount_to_credit > total_charges_amount
          CreditNotes::CreateFromProgressiveBillingInvoice.call(
            progressive_billing_invoice:, amount: amount_to_credit - total_charges_amount
          ).raise_if_error!

          amount_to_credit = total_charges_amount
        end

        if amount_to_credit.positive?
          credit = Credit.create!(
            organization_id: invoice.organization_id,
            invoice:,
            progressive_billing_invoice:,
            amount_cents: amount_to_credit,
            amount_currency: invoice.currency,
            before_taxes: true
          )

          apply_credit_to_fees(fees, progressive_billed_result, credit.amount_cents)

          invoice.sub_total_excluding_taxes_amount_cents -= credit.amount_cents
          invoice.progressive_billing_credit_amount_cents += credit.amount_cents
          result.credits << credit
        end
      end
      result
    end

    private

    attr_reader :invoice, :apply_coupons

    def progressive_billed_amounts
      invoice.invoice_subscriptions.filter_map do |invoice_subscription|
        # Find progressive invoices in the same charge billing period.
        billed = Subscriptions::ProgressiveBilledAmount.call(subscription: invoice_subscription.subscription,
          timestamp: invoice_subscription.charges_from_datetime).raise_if_error!

        if billed.progressive_billing_invoice
          [invoice_subscription.subscription_id, billed]
        end
      end
    end

    def matching_fees(subscription_id, progressive_billing_invoice)
      progressive_fee_keys = progressive_billing_invoice.fees.charge.map { |fee| fee_key(fee) }

      # Use the loaded association so the credit stays visible to the caller's in-memory fees.
      invoice.fees.select do |fee|
        fee.charge? && fee.subscription_id == subscription_id && progressive_fee_keys.include?(fee_key(fee))
      end
    end

    def apply_credit_to_fees(fees, progressive_billed_result, amount_cents)
      # A later progressive invoice includes earlier usage, but its fee subtotals exclude
      # earlier progressive credits. Sum the net fees across the period to recover the
      # amount already billed for each charge, without treating coupons as payments.
      weights = Fee.charge
        .where(invoice_id: progressive_billed_result.invoice_subscriptions.select(:invoice_id))
        .group(:charge_id, :charge_filter_id, :grouped_by)
        .sum("amount_cents - precise_coupons_amount_cents")
      weighted_fees = fees.map { |fee| [fee, weights.fetch(fee_key(fee), 0)] }
      remaining_amount = distribute_credit_to_fees(weighted_fees, amount_cents)

      if remaining_amount.positive?
        weighted_fees = fees.map { |fee| [fee, fee.sub_total_excluding_taxes_amount_cents] }
        distribute_credit_to_fees(weighted_fees, remaining_amount)
      end
    end

    def distribute_credit_to_fees(weighted_fees, amount_cents)
      weighted_fees = weighted_fees.select { |_, weight| weight.positive? }
      remaining_weight = weighted_fees.sum(&:last)
      precision = Fee.columns_hash.fetch("precise_coupons_amount_cents").scale

      # Allocate capped fees first so any remainder is distributed without exceeding
      # another fee's amount after coupons.
      weighted_fees.sort_by { |fee, weight| fee.sub_total_excluding_taxes_amount_cents / weight }.each do |fee, weight|
        fee_credit = [amount_cents * weight / remaining_weight, fee.sub_total_excluding_taxes_amount_cents].min.round(precision)
        fee.precise_coupons_amount_cents += fee_credit
        fee.save!

        amount_cents -= fee_credit
        remaining_weight -= weight
      end

      amount_cents
    end

    def fee_key(fee)
      [fee.charge_id, fee.charge_filter_id, fee.grouped_by]
    end
  end
end
