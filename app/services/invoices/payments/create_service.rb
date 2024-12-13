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

        invoice.update!(payment_attempts: invoice.payment_attempts + 1)

        payment_result = ::PaymentProviders::CreatePaymentFactory.new_instance(
          provider:, invoice:, provider_customer: current_payment_provider_customer
        ).call!

        deliver_error_webhook(payment_result) if payment_result.error_message.present?

        if payment_result.payment.present?
          result.payment = payment_result.payment

          update_invoice_payment_status(
            payment_status: payment_result.payment_status,
            processing: result.payment.status == "processing"
          )

          if result.payment.should_sync_payment?
            Integrations::Aggregator::Payments::CreateJob.perform_later(payment: result.payment)
          end
        elsif payment_result.payment_status.present?
          update_invoice_payment_status(payment_status: payment_result.payment_status)
        end

        result
      rescue BaseService::ServiceFailure => e
        deliver_error_webhook(e.result)
        update_invoice_payment_status(payment_status: e.result.payment_status) if e.result.payment_status.present?

        raise
      end

      def call_async
        return result unless provider

        Invoices::Payments::CreateJob.perform_later(invoice:, payment_provider: provider)

        result.payment_provider = provider
        result
      end

      private

      attr_reader :invoice

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
    end
  end
end
