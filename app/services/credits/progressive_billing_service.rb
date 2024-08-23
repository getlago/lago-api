# frozen_string_literal: true

module Credits
  class ProgressiveBillingService < BaseService
    def initialize(invoice:)
      @invoice = invoice
      super
    end

    def call
      result.credits = []
      return result unless should_create_progressive_billing_credit?

      invoice.invoice_subscriptions.each do |invoice_subscription|
        subscription = invoice_subscription.subscription
        progressive_billing_invoices = subscription
          .invoices
          .progressive_billing
          .finalized
          .where(issuing_date: invoice_subscription.charges_from_datetime...invoice_subscription.charges_to_datetime)
          .order(issuing_date: :asc)

        total_subscription_amount = invoice.fees.charge.where(subscription: subscription).sum(:amount_cents)

        remaining_to_credit = total_subscription_amount

        progressive_billing_invoices.each do |progressive_billing_invoice|
          amount_to_credit = progressive_billing_invoice.fees_amount_cents

          if amount_to_credit > remaining_to_credit
            # TODO: create credit note for (amount_to_credit - remaining_credit)
            invoice.negative_amount_cents -= (amount_to_credit - remaining_to_credit)
            amount_to_credit = remaining_to_credit
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

            remaining_to_credit -= amount_to_credit
          end
        end
      end
      result
    end

    private

    attr_reader :invoice

    def should_create_progressive_billing_credit?
      invoice.invoice_subscriptions.any? do |invoice_subscription|
        invoice_subscription.subscription.invoices.progressive_billing
          .finalized
          .where(issuing_date: invoice_subscription.charges_from_datetime...invoice_subscription.charges_to_datetime)
          .exists?
      end
    end

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
