# frozen_string_literal: true

module Credits
  module ProgressiveBilling
    class AllocateService < BaseService
      Result = BaseResult[:fee_amounts, :credit_note_items]

      def initialize(invoice:, subscription:, progressive_billing_invoice:, amount_cents:)
        @invoice = invoice
        @subscription = subscription
        @progressive_billing_invoice = progressive_billing_invoice
        @amount_cents = amount_cents

        super
      end

      def call
        result.fee_amounts = Hash.new(0)
        remaining_amount = amount_cents
        remaining_fee_amounts = {}

        # Use the loaded association so discounts remain visible to the caller.
        invoice_fees = invoice.fees.select(&:charge?)
        progressive_billing_invoice.fees.order(amount_cents: :desc).each do |progressive_fee|
          available_amount = [progressive_fee.creditable_amount_cents, 0].max
          fee = matching_fee(invoice_fees, progressive_fee)

          if fee
            allocated_amount = invoice_fee_amount(fee, available_amount:, remaining_amount:)
            result.fee_amounts[fee] += allocated_amount
            remaining_amount -= allocated_amount
            available_amount -= allocated_amount
          end
          remaining_fee_amounts[progressive_fee] = available_amount
        end

        result.credit_note_items = credit_note_items(remaining_fee_amounts, remaining_amount:)
        result
      end

      private

      attr_reader :invoice, :subscription, :progressive_billing_invoice, :amount_cents

      def matching_fee(invoice_fees, progressive_fee)
        invoice_fees.find do |fee|
          fee.subscription_id == subscription.id &&
            fee.charge_id == progressive_fee.charge_id &&
            fee.charge_filter_id == progressive_fee.charge_filter_id &&
            fee.grouped_by == progressive_fee.grouped_by
        end
      end

      def invoice_fee_amount(fee, available_amount:, remaining_amount:)
        undiscounted_amount = fee.amount_cents - fee.precise_coupons_amount_cents - result.fee_amounts[fee]
        [remaining_amount, available_amount, undiscounted_amount].min.clamp(0, remaining_amount)
      end

      def credit_note_items(remaining_fee_amounts, remaining_amount:)
        items = []
        remaining_fee_amounts.each do |fee, available_amount|
          break unless remaining_amount.positive?

          amount = [remaining_amount, available_amount].min
          next unless amount.positive?

          items << {fee_id: fee.id, amount_cents: amount}
          remaining_amount -= amount
        end
        items
      end
    end
  end
end
