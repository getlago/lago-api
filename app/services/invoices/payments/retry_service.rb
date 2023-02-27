# frozen_string_literal: true

module Invoices
  module Payments
    class RetryService < BaseService
      WEBHOOK_TYPE = {
        'subscription' => 'invoice.created',
        'credit' => 'invoice.paid_credit_added',
        'add_on' => 'invoice.add_on_added',
      }.freeze

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

        deliver_webhook if customer&.organization&.webhook_url?
        Invoices::Payments::CreateService.new(invoice).call

        result.invoice = invoice

        result
      end

      private

      attr_reader :invoice

      delegate :customer, to: :invoice

      def deliver_webhook
        SendWebhookJob.perform_later(WEBHOOK_TYPE[invoice.invoice_type], invoice)
      end
    end
  end
end
