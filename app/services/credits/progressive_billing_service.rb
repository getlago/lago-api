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

        # We can use invoice_subscription.charges_from_datetime as we're looking for the progressive billing invoices
        # that are associated to a subscription with boundaries charges_from_datetime <= timestamp; charges_to_datetime > timestamp
        progressive_billed_result = Subscriptions::ProgressiveBilledAmount.call(subscription:,
          timestamp: invoice_subscription.charges_from_datetime).raise_if_error!
        progressive_billing_invoice = progressive_billed_result.progressive_billing_invoice

        next unless progressive_billing_invoice

        total_charges_amount = invoice.fees.charge.where(subscription: subscription).sum(:amount_cents)

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
