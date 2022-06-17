# frozen_string_literal: true

module Invoices
  module Payments
    class StripeService < BaseService
      def initialize(invoice)
        @invoice = invoice

        super(nil)
      end

      def create
        return result unless should_process_payment?

        ensure_provider_customer

        stripe_result = Stripe::Charge.create(
          stripe_payment_payload,
          {
            api_key: api_key,
            idempotency_key: invoice.id,
          },
        )

        payment = Payment.new(
          invoice: invoice,
          payment_provider: organization.stripe_provider,
          payment_provider_customer: customer.stripe_customer,
          amount_cents: stripe_result.amount,
          amount_currency: stripe_result.currency&.upcase,
          payment_id: stripe_result.id,
          status: stripe_result.status,
        )
        payment.save!

        update_invoice_status(payment.status)

        result.invoice = invoice
        result.payment = payment
        result
      end

      private

      attr_accessor :invoice

      delegate :organization, :customer, to: :invoice

      def should_process_payment?
        return false unless organization.stripe_payment_provider
        return true if invoice.total_amount_cents.positive?

        organization.stripe_payment_provider.send_zero_amount_invoice?
      end

      def ensure_provider_customer
        return if customer&.stripe_customer&.provider_customer_id

        # TODO: create customer on stripe
        #       wait for merge of https://github.com/getlago/lago-api/pull/268
      end

      def stripe_api_key
        organization.stripe_payment_provider.secret_key
      end

      def stripe_payment_payload
        {
          amount: invoice.total_amount_cents,
          currency: invoice.total_amount_currency.downcase,
          customer: customer.stripe_customer.provider_customer_id,
          description: '', # TODO
          metadata: {
            lago_customer_id: customer.id,
            lago_invoice_id: invoice.id,
            invoice_issuing_date: invoice.issuing_date.iso8601,
            invoice_from_date: invoice.from_date.iso8601,
            invoice_to_date: invoice.to_date.iso8601,
            invoice_type: invoice.invoice_type,
          },
        }
      end

      def update_invoice_status(status)
        return unless Invoice::STATUS.include?(status&.to_sym)

        invoice.update!(status: status)
      end
    end
  end
end
