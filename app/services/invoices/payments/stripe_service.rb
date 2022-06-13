# frozen_string_literal: true

module Invoices
  module Payments
    class StripeService < BaseService
      def initialize(invoice)
        @invoice = invoice

        super(nil)
      end

      def create
        Stripe::Charge.create(
          amount: invoice.total_amount_cents,
          currency: invoice.total_amount_currency.downcase,
          # customer: customer.stripe_customer&.provider_customer_id,
          description: '', # TODO
          metadata: {
            lago_customer_id: customer.id,
            lago_invoice_id: invoice.id,
            invoice_issuing_date: invoice.issuing_date.iso8601,
            invoice_from_date: invoice.from_date.iso8601,
            invoice_to_date: invoice.to_date.iso8601,
            invoice_type: invoice.invoice_type,
          },
        )
      end

      private

      attr_accessor :invoice

      delegate :organization, :customer, to: :invoice

      def stripe_api_key
        # TODO: organization.stripe_payment_provider.secret_key
      end
    end
  end
end
