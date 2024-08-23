# frozen_string_literal: true

module CreditNotes
  class CreateFromProgressiveBillingInvoice < BaseService
    def initialize(progressive_billing_invoice:, amount:, reason: :other)
      @progressive_billing_invoice = progressive_billing_invoice
      @amount = amount
      @reason = reason

      super
    end

    def call
      return result unless amount.positive?

      # Important to call this method as it modifies @amount if needed
      items = calculate_items!

      CreditNotes::CreateService.new(
        invoice: progressive_billing_invoice,
        credit_amount_cents: amount,
        items:,
        reason:,
        automatic: true
      ).call.raise_if_error!
    end

    private

    attr_reader :progressive_billing_invoice, :amount, :reason

    def calculate_items!
      items = []
      remaining = amount

      # The amount can be greater than a single fee amount. We'll keep on deducting until we've credited enough
      progressive_billing_invoice.fees.each do |fee|
        # no further credit remaining
        break if remaining.zero?

        # take the lower value of remaining or maximum creditable for this fee. (whichever is the lowest)
        fee_credit_amount = [remaining, fee.creditable_amount_cents].min
        items << {
          fee_id: fee.id,
          amount_cents: fee_credit_amount.truncate(CreditNote::DB_PRECISION_SCALE)
        }

        remaining -= fee_credit_amount
      end

      # it could be that we have some amount remaining
      # TODO: verify and check in v2
      if remaining.positive?
        @amount -= remaining
      end

      items
    end
  end
end
