# frozen_string_literal: true

module PaymentRequests
  module Payments
    class CreateService < BaseService
      include Customers::PaymentProviderFinder

      def initialize(payable:, payment_provider: nil)
        @payable = payable
        @provider = payment_provider&.to_sym

        super
      end

      def call
        return result.not_found_failure!(resource: "payment_provider") unless provider

        result.payable = payable
        return result unless should_process_payment?

        unless payable.total_amount_cents.positive?
          update_payable_payment_status(payment_status: :succeeded)
          return result
        end

        if processing_payment
          # Payment is being processed, return the existing payment
          # Status will be updated via webhooks
          result.payment = processing_payment
          return result
        end

        payable.increment_payment_attempts!

        payment ||= Payment.create_with(
          payment_provider_id: current_payment_provider.id,
          payment_provider_customer_id: current_payment_provider_customer.id,
          amount_cents: payable.total_amount_cents,
          amount_currency: payable.currency,
          status: "pending"
        ).find_or_create_by!(
          payable:,
          payable_payment_status: "pending"
        )

        result.payment = payment

        payment_result = ::PaymentProviders::CreatePaymentFactory.new_instance(
          provider:,
          payment:,
          reference: "#{organization.name} - Overdue invoices",
          metadata: {
            lago_customer_id: payable.customer_id,
            lago_payable_id: payable.id,
            lago_payable_type: payable.class.name
          }
        ).call!

        update_payable_payment_status(payment_status: payment_result.payment.payable_payment_status)
        update_invoices_payment_status(payment_status: payment_result.payment.payable_payment_status)

        PaymentRequestMailer.with(payment_request: payable).requested.deliver_later if payable.payment_failed?

        result
      rescue BaseService::ServiceFailure => e
        result.payment = e.result.payment
        deliver_error_webhook(e.result)
        update_payable_payment_status(payment_status: e.result.payment.payable_payment_status)

        # Some errors should be investigated and need to be raised
        raise if e.result.reraise

        result
      end

      def call_async
        return result.not_found_failure!(resource: "payment_provider") unless provider

        PaymentRequests::Payments::CreateJob.perform_later(payable:, payment_provider: provider)

        result.payment_provider = provider
        result
      end

      private

      attr_reader :payable

      delegate :customer, :organization, to: :payable

      def provider
        @provider ||= payable.customer.payment_provider&.to_sym
      end

      def should_process_payment?
        return false if payable.payment_succeeded?
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

      def update_payable_payment_status(payment_status:)
        PaymentRequests::UpdateService.call!(
          payable: payable,
          params: {
            # NOTE: A proper `processing` payment status should be introduced for invoices
            payment_status: (payment_status.to_s == "processing") ? :pending : payment_status,
            ready_for_payment_processing: payment_status.to_sym == :failed
          },
          webhook_notification: payment_status.to_sym == :succeeded
        )
      end

      def update_invoices_payment_status(payment_status:)
        payable.invoices.each do |invoice|
          Invoices::UpdateService.call!(
            invoice:,
            params: {
              # NOTE: A proper `processing` payment status should be introduced for invoices
              payment_status: (payment_status.to_s == "processing") ? :pending : payment_status,
              ready_for_payment_processing: payment_status.to_sym == :failed
            },
            webhook_notification: payment_status.to_sym == :succeeded
          )
        end
      end

      def deliver_error_webhook(payment_result)
        DeliverErrorWebhookService.call_async(payable, {
          provider_customer_id: current_payment_provider_customer.provider_customer_id,
          provider_error: {
            message: payment_result.error_message,
            error_code: payment_result.error_code
          }
        })
      end

      def processing_payment
        @processing_payment ||= Payment.find_by(
          payable_id: payable.id,
          payment_provider_id: current_payment_provider.id,
          payment_provider_customer_id: current_payment_provider_customer.id,
          amount_cents: payable.total_amount_cents,
          amount_currency: payable.currency,
          payable_payment_status: "processing"
        )
      end
    end
  end
end
