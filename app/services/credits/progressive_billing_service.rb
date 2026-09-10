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
        billed_amount = Subscriptions::ProgressiveBilledAmount.call!(
          subscription: invoice_subscription.subscription,
          timestamp: invoice_subscription.charges_from_datetime
        )
        next unless billed_amount.progressive_billing_invoice

        allocation = ProgressiveBilling::AllocateService.call!(
          invoice:,
          subscription: invoice_subscription.subscription,
          progressive_billing_invoice: billed_amount.progressive_billing_invoice,
          amount_cents: billed_amount.to_invoice_amount
        )

        create_credit_note(billed_amount, allocation.credit_note_items)
        apply_invoice_credit(billed_amount.progressive_billing_invoice, allocation.fee_amounts)
      end

      result
    end

    private

    attr_reader :invoice

    def create_credit_note(billed_amount, items)
      if items.any? && billed_amount.to_credit_amount.positive?
        # Credit note items are gross; the service deducts their coupons exactly once.
        CreditNotes::CreateFromProgressiveBillingInvoice.call!(
          progressive_billing_invoice: billed_amount.progressive_billing_invoice,
          amount: items.sum { |item| item[:amount_cents] },
          fee_items: items
        )
      end
    end

    def apply_invoice_credit(progressive_billing_invoice, fee_amounts)
      amount_cents = fee_amounts.values.sum
      return unless amount_cents.positive?

      credit = Credit.create!(
        organization_id: invoice.organization_id,
        invoice:,
        progressive_billing_invoice:,
        amount_cents:,
        amount_currency: invoice.currency,
        before_taxes: true
      )

      apply_fee_discounts(fee_amounts)
      invoice.sub_total_excluding_taxes_amount_cents -= credit.amount_cents
      invoice.progressive_billing_credit_amount_cents += credit.amount_cents
      result.credits << credit
    end

    def apply_fee_discounts(fee_amounts)
      fee_amounts.each do |fee, amount|
        fee.precise_coupons_amount_cents += amount
        fee.save!
      end
    end
  end
end
