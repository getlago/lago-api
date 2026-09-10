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

        fee_amounts, credit_note_items = allocate_gross_amount(progressive_billed_result, subscription:)
        amount_to_credit = fee_amounts.values.sum

        if credit_note_items.any? && progressive_billed_result.to_credit_amount.positive?
          # Credit note items are gross; the service deducts their coupons exactly once.
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

          fee_amounts.each do |fee, amount|
            fee.precise_coupons_amount_cents += amount
            fee.save!
          end

          invoice.sub_total_excluding_taxes_amount_cents -= credit.amount_cents
          invoice.progressive_billing_credit_amount_cents += credit.amount_cents
          result.credits << credit
        end
      end
      result
    end

    private

    attr_reader :invoice

    def allocate_gross_amount(progressive_billed_result, subscription:)
      remaining_amount = progressive_billed_result.to_invoice_amount
      fee_amounts = Hash.new(0)
      remaining_fee_amounts = {}
      # Use the loaded association so discounts remain visible to the caller.
      invoice_fees = invoice.fees.select(&:charge?)

      progressive_billed_result.progressive_billing_invoice.fees.order(amount_cents: :desc).each do |progressive_fee|
        available_amount = [progressive_fee.creditable_amount_cents, 0].max
        fee = invoice_fees.find { |current_fee|
          current_fee.subscription_id == subscription.id &&
            current_fee.charge_id == progressive_fee.charge_id &&
            current_fee.charge_filter_id == progressive_fee.charge_filter_id &&
            current_fee.grouped_by == progressive_fee.grouped_by
        }

        if fee
          amount = [remaining_amount, available_amount, fee.amount_cents - fee.precise_coupons_amount_cents - fee_amounts[fee]].min.clamp(0, remaining_amount)
          fee_amounts[fee] += amount
          remaining_amount -= amount
          available_amount -= amount
        end
        remaining_fee_amounts[progressive_fee] = available_amount
      end

      credit_note_items = []
      remaining_fee_amounts.each do |fee, available_amount|
        break unless remaining_amount.positive?

        amount = [remaining_amount, available_amount].min
        next unless amount.positive?

        credit_note_items << {fee_id: fee.id, amount_cents: amount}
        remaining_amount -= amount
      end

      [fee_amounts, credit_note_items]
    end
  end
end
