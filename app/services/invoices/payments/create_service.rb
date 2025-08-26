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
          organization_id: invoice.organization_id,
          payment_provider_id: current_payment_provider.id,
          payment_provider_customer_id: current_payment_provider_customer.id,
          amount_cents: invoice.total_due_amount_cents,
          amount_currency: invoice.currency,
          status: "pending",
          customer_id: invoice.customer_id
        ).find_or_create_by!(
          payable: invoice,
          payable_payment_status: "pending"
        )

        result.payment = payment

        payment_result = ::PaymentProviders::CreatePaymentFactory.new_instance(
          provider:,
          payment:,
          reference: "#{invoice.billing_entity.name} - Invoice #{invoice.number}",
          metadata: {
            lago_invoice_id: invoice.id,
            lago_customer_id: invoice.customer_id,
            invoice_issuing_date: invoice.issuing_date.iso8601,
            invoice_type: invoice.invoice_type
          }
        ).call!

        payment_status = payment_result.payment.payable_payment_status
        update_invoice_payment_status(payment_status:)

        Integrations::Aggregator::Payments::CreateJob.perform_later(payment:) if result.payment.should_sync_payment?

        result
      rescue BaseService::ServiceFailure => e
        result.payment = e.result.payment

        if e.result.payment.payable_payment_status&.to_sym != :pending
          # Avoid notification for amount_too_small errors
          deliver_error_webhook(e)
        end

        update_invoice_payment_status(payment_status: e.result.payment.payable_payment_status)

        # Some errors should be investigated and need to be raised
        raise if e.result.reraise

        result
      end

      def call_async
        return result unless provider

        Invoices::Payments::CreateJob.perform_after_commit(invoice:, payment_provider: provider)

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
        return false if invoice.self_billed?
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

      def update_invoice_payment_status(payment_status:)
        params = {
          # NOTE: A proper `processing` payment status should be introduced for invoices
          payment_status: (payment_status.to_s == "processing") ? :pending : payment_status,
          ready_for_payment_processing: %w[pending failed].include?(payment_status.to_s)
        }

        if payment_status.to_s == "succeeded"
          total_paid_amount_cents = invoice.payments.where(payable_payment_status: :succeeded).sum(:amount_cents)
          params[:total_paid_amount_cents] = total_paid_amount_cents
        end

        Invoices::UpdateService.call!(
          invoice:,
          params:,
          webhook_notification: payment_status.to_sym == :succeeded
        )
      end

      def deliver_error_webhook(e)
        payment_result = e.result

        DeliverErrorWebhookService.call_async(invoice, {
          provider_customer_id: current_payment_provider_customer.provider_customer_id,
          provider_error: {
            message: payment_result.error_message,
            error_code: payment_result.error_code
          },
          error_details: e.original_error ? V1::Errors::ErrorSerializerFactory.new_instance(e.original_error).serialize : {}
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
