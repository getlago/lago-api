# frozen_string_literal: true

module Credits
  class ProgressiveBillingService < BaseService
    Result = BaseResult[:credits]

    def initialize(invoice:)
      @invoice = invoice
      super
    end

    def call
      result.credits = []

      invoice.invoice_subscriptions.each do |invoice_subscription|
        subscription = invoice_subscription.subscription

        # We can use invoice_subscription.charges_from_datetime as we're looking for the progressive billing invoices
        # that are associated to a subscription with boundaries charges_from_datetime <= timestamp; charges_to_datetime > timestamp
        progressive_billed_result = Subscriptions::ProgressiveBilledAmount.call(subscription:,
          timestamp: invoice_subscription.charges_from_datetime).raise_if_error!
        progressive_billing_invoice = progressive_billed_result.progressive_billing_invoice

        next unless progressive_billing_invoice

        amount_to_credit, credit_note_items = apply_credit_to_fees(
          progressive_billing_invoice, subscription:, amount_cents: progressive_billed_result.to_invoice_amount
        )

        if credit_note_items.any? && progressive_billed_result.to_credit_amount.positive?
          CreditNotes::CreateFromProgressiveBillingInvoice.call(
            progressive_billing_invoice:,
            amount: credit_note_items.sum { |item| item[:amount_cents] },
            fee_items: credit_note_items
          ).raise_if_error!
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

          invoice.sub_total_excluding_taxes_amount_cents -= credit.amount_cents
          invoice.progressive_billing_credit_amount_cents += credit.amount_cents
          result.credits << credit
        end
      end
      result
    end

    private

    attr_reader :invoice

    def apply_credit_to_fees(progressive_billing_invoice, subscription:, amount_cents:)
      remaining_amount = amount_cents
      remaining_fee_amounts = {}
      # Use the loaded association so the credit stays visible to the caller's in-memory fees.
      invoice_fees = invoice.fees.select { |fee| fee.charge? && fee.subscription_id == subscription.id }
      progressive_billing_invoice.fees.order(amount_cents: :desc).each do |progressive_fee|
        available_amount = [progressive_fee.creditable_amount_cents, 0].max
        fee = invoice_fees.find { |f|
          f.charge_id == progressive_fee.charge_id &&
            f.charge_filter_id == progressive_fee.charge_filter_id &&
            f.grouped_by == progressive_fee.grouped_by
        }

        if fee
          amount = [remaining_amount, available_amount, fee.amount_cents - fee.precise_coupons_amount_cents].min.clamp(0, remaining_amount)
          fee.precise_coupons_amount_cents += amount
          fee.save!
          remaining_amount -= amount
          available_amount -= amount
        end
        remaining_fee_amounts[progressive_fee] = available_amount
      end

      applied_amount = amount_cents - remaining_amount
      credit_note_items = remaining_fee_amounts.filter_map do |fee, available_amount|
        amount = [remaining_amount, available_amount].min
        next unless amount.positive?

        remaining_amount -= amount
        {fee_id: fee.id, amount_cents: amount}
      end

      [applied_amount, credit_note_items]
    end
  end
end
