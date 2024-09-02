# frozen_string_literal: true

module Credits
  class ProgressiveBillingService < BaseService
    def initialize(invoice:)
      @invoice = invoice
      super
    end

    def call
      result.credits = []

      invoice.invoice_subscriptions.each do |invoice_subscription|
        subscription = invoice_subscription.subscription

        # We can use invoice_subscription.timestamp as that will _always_ be between the subscription charges_from and to times
        progressive_billed_result = Subscriptions::ProgressiveBilledAmount.call(subscription:, timestamp: invoice_subscription.timestamp).raise_if_error!
        progressive_billing_invoice = progressive_billed_result.progressive_billing_invoice

        next unless progressive_billing_invoice

        total_charges_amount = invoice.fees.charge.where(subscription: subscription).sum(:amount_cents)

        amount_to_credit = progressive_billing_invoice.fees_amount_cents

        if amount_to_credit > total_charges_amount
          CreditNotes::CreateFromProgressiveBillingInvoice.call(
            progressive_billing_invoice:, amount: amount_to_credit - total_charges_amount
          ).raise_if_error!

          amount_to_credit = total_charges_amount
        end

        if amount_to_credit.positive?
          credit = Credit.create!(
            invoice:,
            progressive_billing_invoice:,
            amount_cents: amount_to_credit,
            amount_currency: invoice.currency,
            before_taxes: true
          )

          apply_credit_to_fees(credit)

          invoice.sub_total_excluding_taxes_amount_cents -= credit.amount_cents
          invoice.progressive_billing_credit_amount_cents += credit.amount_cents
          result.credits << credit
        end
      end
      result
    end

    private

    attr_reader :invoice

    def apply_credit_to_fees(credit)
      invoice.fees.charge.reload.each do |fee|
        fee.precise_coupons_amount_cents += (
          credit.amount_cents * (fee.amount_cents - fee.precise_coupons_amount_cents)
        ).fdiv(invoice.sub_total_excluding_taxes_amount_cents)

        fee.precise_coupons_amount_cents = fee.amount_cents if fee.amount_cents < fee.precise_coupons_amount_cents
        fee.save!
      end
    end
  end
end
