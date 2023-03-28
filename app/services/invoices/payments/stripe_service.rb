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
          update_invoice_payment_status(payment_status: :succeeded)
          return result
        end

        increment_payment_attempts

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

        update_invoice_payment_status(payment_status: payment.status.to_sym)

        result.payment = payment
        result
      end

      def update_payment_status(provider_payment_id:, status:, metadata: {})
        payment = Payment.find_by(provider_payment_id:)
        return handle_missing_payment(metadata) unless payment

        result.payment = payment
        result.invoice = payment.invoice
        return result if payment.invoice.succeeded?

        payment.update!(status:)

        update_invoice_payment_status(payment_status: status.to_sym)

        result
      rescue BaseService::FailedResult => e
        result.fail_with_error!(e)
      end

      private

      attr_accessor :invoice

      delegate :organization, :customer, to: :invoice

      def should_process_payment?
        return false if invoice.succeeded?
        return false if organization.stripe_payment_provider.blank?

        customer&.stripe_customer&.provider_customer_id
      end

      def stripe_api_key
        organization.stripe_payment_provider.secret_key
      end

      def stripe_payment_method
        payment_method_id = customer.stripe_customer.payment_method_id

        if payment_method_id
          # NOTE: Check if payment method still exists
          customer_service = PaymentProviderCustomers::StripeService.new(customer.stripe_customer)
          customer_service_result = customer_service.check_payment_method(payment_method_id)
          return customer_service_result.payment_method.id if customer_service_result.success?
        end

        # NOTE: Retrieve list of existing payment_methods
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
            idempotency_key: "#{invoice.id}/#{invoice.payment_attempts}",
          },
        )
      rescue Stripe::CardError, Stripe::InvalidRequestError => e
        deliver_error_webhook(e)
        update_invoice_payment_status(payment_status: :failed, deliver_webhook: false)

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
          error_on_requires_action: true,
          description: "#{organization.name} - Invoice #{invoice.number}",
          metadata: {
            lago_customer_id: customer.id,
            lago_invoice_id: invoice.id,
            invoice_issuing_date: invoice.issuing_date.iso8601,
            invoice_type: invoice.invoice_type,
          },
        }
      end

      def update_invoice_payment_status(payment_status:, deliver_webhook: true)
        result = Invoices::UpdateService.call(
          invoice:,
          params: {
            payment_status:,
            ready_for_payment_processing: payment_status.to_sym != :succeeded,
          },
          webhook_notification: deliver_webhook,
        )
        result.raise_if_error!
      end

      def increment_payment_attempts
        invoice.update!(payment_attempts: invoice.payment_attempts + 1)
      end

      def deliver_error_webhook(stripe_error)
        return unless invoice.organization.webhook_url?

        SendWebhookJob.perform_later(
          'invoice.payment_failure',
          invoice,
          provider_customer_id: customer.stripe_customer.provider_customer_id,
          provider_error: {
            message: stripe_error.message,
            error_code: stripe_error.code,
          },
        )
      end

      def handle_missing_payment(metadata)
        # NOTE: Payment was not initiated by lago
        return result unless metadata&.key?(:lago_invoice_id)

        # NOTE: Invoice does not belong to this lago instance
        return result if Invoice.find_by(id: metadata[:lago_invoice_id]).nil?

        result.not_found_failure!(resource: 'stripe_payment')
      end
    end
  end
end
