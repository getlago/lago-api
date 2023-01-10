# frozen_string_literal: true

module Invoices
  module Payments
    class RetryService < BaseService
      def initialize(invoice:)
        @invoice = invoice

        super
      end

      def call
        return result.not_found_failure!(resource: 'invoice') if invoice.blank?
        return result.not_allowed_failure!(code: 'invalid_status') if invoice.draft? || invoice.succeeded?

        unless invoice.ready_for_payment_processing?
          return result.not_allowed_failure!(code: 'payment_processor_is_currently_handling_payment')
        end

        SendWebhookJob.perform_later(webhook_type, invoice) if customer&.organization&.webhook_url?
        Invoices::Payments::CreateService.new(invoice).call

        result.invoice = invoice

        result
      end

      private

      attr_reader :invoice

      delegate :customer, to: :invoice

      def webhook_type
        return :invoice if invoice.invoice_type == 'subscription'

        invoice.invoice_type.to_sym
      end
    end
  end
end
