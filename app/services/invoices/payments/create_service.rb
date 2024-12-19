# frozen_string_literal: true

module Invoices
  module Payments
    class CreateService < BaseService
      include Customers::PaymentProviderFinder

      def initialize(invoice:, payment_provider: nil)
        @invoice = invoice
        @provider = payment_provider&.to_sym

        super
      end

      def call
        result.invoice = invoice
        return result unless should_process_payment?

        unless invoice.total_amount_cents.positive?
          update_invoice_payment_status(payment_status: :succeeded)
          return result
        end

        if processing_payment
          # Payment is being processed, return the existing payment
          # Status will be updated via webhooks
          result.payment = processing_payment
          return result
        end

        invoice.update!(payment_attempts: invoice.payment_attempts + 1)

        payment ||= Payment.create_with(
          payment_provider_id: current_payment_provider.id,
          payment_provider_customer_id: current_payment_provider_customer.id,
          amount_cents: invoice.total_amount_cents,
          amount_currency: invoice.currency
        ).find_or_create_by!(
          payable: invoice,
          payable_payment_status: "pending",
          status: "pending"
        )

        result.payment = payment

        payment_result = ::PaymentProviders::CreatePaymentFactory.new_instance(provider:, payment:).call!

        payment_status = payment_result.payment.payable_payment_status
        update_invoice_payment_status(
          payment_status: (payment_status == "processing") ? :pending : payment_status,
          processing: payment_status == "processing"
        )

        Integrations::Aggregator::Payments::CreateJob.perform_later(payment:) if result.payment.should_sync_payment?

        result
      rescue BaseService::ServiceFailure => e
        result.payment = e.result.payment
        deliver_error_webhook(e.result)

        if e.result.payment.payable_payment_status&.to_sym != :pending
          update_invoice_payment_status(payment_status: e.result.payment.payable_payment_status)
        end

        # Some errors should be investigated and need to be raised
        raise if e.result.reraise

        result
      end

      def call_async
        return result unless provider

        Invoices::Payments::CreateJob.perform_later(invoice:, payment_provider: provider)

        result.payment_provider = provider
        result
      end

      private

      attr_reader :invoice, :payment

      delegate :customer, to: :invoice

      def provider
        @provider ||= invoice.customer.payment_provider&.to_sym
      end

      def should_process_payment?
        return false if invoice.payment_succeeded? || invoice.voided?
        return false if current_payment_provider.blank?

        current_payment_provider_customer&.provider_customer_id
      end

      def current_payment_provider
        @current_payment_provider ||= payment_provider(customer)
      end

      def current_payment_provider_customer
        @current_payment_provider_customer ||= customer.payment_provider_customers
          .find_by(payment_provider_id: current_payment_provider.id)
      end

      def update_invoice_payment_status(payment_status:, processing: false)
        Invoices::UpdateService.call!(
          invoice: invoice,
          params: {
            payment_status:,
            # NOTE: A proper `processing` payment status should be introduced for invoices
            ready_for_payment_processing: !processing && payment_status.to_sym != :succeeded
          },
          webhook_notification: payment_status.to_sym == :succeeded
        )
      end

      def deliver_error_webhook(payment_result)
        DeliverErrorWebhookService.call_async(invoice, {
          provider_customer_id: current_payment_provider_customer.provider_customer_id,
          provider_error: {
            message: payment_result.error_message,
            error_code: payment_result.error_code
          }
        })
      end

      def processing_payment
        @processing_payment ||= Payment.find_by(
          payable: invoice,
          payment_provider_id: current_payment_provider.id,
          payment_provider_customer_id: current_payment_provider_customer.id,
          amount_cents: invoice.total_amount_cents,
          amount_currency: invoice.currency,
          payable_payment_status: "processing"
        )
      end
    end
  end
end
