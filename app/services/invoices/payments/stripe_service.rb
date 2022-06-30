# frozen_string_literal: true

module Invoices
  module Payments
    class StripeService < BaseService
      def initialize(invoice = nil)
        @invoice = invoice

        super(nil)
      end

      def create
        result.invoice = invoice
        return result unless should_process_payment?

        unless invoice.total_amount_cents.positive?
          update_invoice_status(:succeeded)
          return result
        end

        ensure_provider_customer

        stripe_result = create_stripe_payment

        payment = Payment.new(
          invoice: invoice,
          payment_provider_id: organization.stripe_payment_provider.id,
          payment_provider_customer_id: customer.stripe_customer.id,
          amount_cents: stripe_result.amount,
          amount_currency: stripe_result.currency&.upcase,
          provider_payment_id: stripe_result.id,
          status: stripe_result.status,
        )
        payment.save!

        update_invoice_status(payment.status)

        result.payment = payment
        result
      end

      def update_status(provider_payment_id:, status:)
        payment = Payment.find_by(provider_payment_id: provider_payment_id)
        return result.fail!('stripe_payment_not_found') unless payment

        result.payment = payment
        result.invoice = payment.invoice
        return result if payment.invoice.succeeded?

        payment.update!(status: status)
        payment.invoice.update!(status: status)
        result
      rescue ArgumentError
        result.fail!('invalid_invoice_status')
      end

      private

      attr_accessor :invoice

      delegate :organization, :customer, to: :invoice

      def should_process_payment?
        return false if invoice.succeeded?

        organization.stripe_payment_provider.present?
      end

      def ensure_provider_customer
        return if customer.stripe_customer&.provider_customer_id

        customer_result = PaymentProviderCustomers::CreateService.new(customer)
          .create_or_update(
            customer_class: PaymentProviderCustomers::StripeCustomer,
            payment_provider_id: organization.stripe_payment_provider.id,
            params: {},
            async: false,
          )
        customer_result.throw_error

        # NOTE: stripe customer is created on an other instance of the customer
        customer.reload
      end

      def stripe_api_key
        organization.stripe_payment_provider.secret_key
      end

      def stripe_payment_method
        payment_method = customer.stripe_customer.payment_method_id
        return payment_method if payment_method.present?

        payment_method = Stripe::PaymentMethod.list(
          {
            customer: customer.stripe_customer.provider_customer_id,
            type: 'card', # TODO: Supported payment method type
          },
          {
            api_key: stripe_api_key,
          },
        ).first
        customer.stripe_customer.payment_method_id = payment_method&.id
        customer.stripe_customer.save!

        payment_method&.id
      end

      def create_stripe_payment
        Stripe::PaymentIntent.create(
          stripe_payment_payload,
          {
            api_key: stripe_api_key,
            idempotency_key: invoice.id,
          },
        )
      rescue Stripe::CardError => e
        deliver_error_webhook(e)
        update_invoice_status(:failed)

        raise
      end

      def stripe_payment_payload
        {
          amount: invoice.total_amount_cents,
          currency: invoice.total_amount_currency.downcase,
          customer: customer.stripe_customer.provider_customer_id,
          payment_method: stripe_payment_method,
          confirm: true,
          off_session: true,
          receipt_email: customer.email,
          error_on_requires_action: true,
          description: "Lago - #{organization.name} - Invoice #{invoice.number}",
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

      def deliver_error_webhook(stripe_error)
        return unless invoice.organization.webhook_url?

        SendWebhookJob.perform_later(
          :payment_provider_invoice_payment_error,
          invoice,
          provider_customer_id: customer.stripe_customer.provider_customer_id,
          provider_error: {
            message: stripe_error.message,
            error_code: stripe_error.code,
          },
        )
      end
    end
  end
end
