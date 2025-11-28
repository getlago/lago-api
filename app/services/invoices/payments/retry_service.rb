# frozen_string_literal: true

module Invoices
  module Payments
    class RetryService < BaseService
      def initialize(invoice:)
        @invoice = invoice

        super
      end

      def call
        return result.not_found_failure!(resource: "invoice") if invoice.blank?

        if invoice.draft? || invoice.voided? || invoice.payment_succeeded?
          return result.not_allowed_failure!(code: "invalid_status")
        end

        unless invoice.ready_for_payment_processing?
          return result.not_allowed_failure!(code: "payment_processor_is_currently_handling_payment")
        end

        if invoice.customer.payment_provider.nil?
          Utils::ActivityLog.produce(invoice, "invoice.payment_failure")
          SendWebhookJob.perform_later("invoice.payment_failure", invoice, {provider_error: {error_message: "no linked_payment provider", error_code: "no_linked_payment_provider"}})
          return result.single_validation_failure!(error_code: "no_linked_payment_provider")
        end

        Invoices::Payments::CreateService.call_async(invoice:)

        result.invoice = invoice

        result
      end

      private

      attr_reader :invoice

      delegate :customer, to: :invoice
    end
  end
end
