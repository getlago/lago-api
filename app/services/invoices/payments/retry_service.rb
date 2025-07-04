# frozen_string_literal: true

module Invoices
  module Payments
    class RetryService < BaseService
      WEBHOOK_TYPE = {
        "subscription" => "invoice.created",
        "credit" => "invoice.paid_credit_added",
        "add_on" => "invoice.add_on_added",
        "one_off" => "invoice.one_off_created",
        "progressive_billing" => "invoice.created"
      }.freeze

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

        deliver_webhook
        produce_activity_log
        Invoices::Payments::CreateService.call_async(invoice:)

        result.invoice = invoice

        result
      end

      private

      attr_reader :invoice

      delegate :customer, to: :invoice

      def deliver_webhook
        SendWebhookJob.perform_later(WEBHOOK_TYPE[invoice.invoice_type], invoice)
      end

      def produce_activity_log
        return unless Clickhouse::ActivityLog::ACTIVITY_TYPES.value? WEBHOOK_TYPE[invoice.invoice_type]

        Utils::ActivityLog.produce(invoice, WEBHOOK_TYPE[invoice.invoice_type])
      end
    end
  end
end
