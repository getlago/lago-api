# frozen_string_literal: true

module Invoices
  module Payments
    class RetryService < BaseService
      Result = BaseResult[:invoice, :payment_method]

      # v1 keeps accepting any payment method override and ignoring what it cannot use; v2
      # refuses an override that would not charge the method it names.
      def initialize(invoice:, payment_method_params: {}, validate_payment_method: false)
        @invoice = invoice
        @payment_method_params = payment_method_params
        @validate_payment_method = validate_payment_method

        super
      end

      def call
        return result.not_found_failure!(resource: "invoice") if invoice.blank?
        return result if validate_payment_method && !valid_payment_method?

        if invoice.draft? || invoice.voided? || invoice.payment_succeeded?
          return result.not_allowed_failure!(code: "invalid_status")
        end

        unless invoice.ready_for_payment_processing?
          return result.not_allowed_failure!(code: "payment_processor_is_currently_handling_payment")
        end

        create_result = Invoices::Payments::CreateService.call_async(invoice:, payment_method_params:)
        deliver_webhook if create_result.payment_provider.nil?

        result.invoice = invoice

        result
      end

      private

      attr_reader :invoice, :payment_method_params, :validate_payment_method

      delegate :customer, to: :invoice

      def valid_payment_method?
        if payment_method_params.present? && payment_method_params[:payment_method_id].present?
          result.payment_method = customer.payment_methods.find_by(id: payment_method_params[:payment_method_id])
        end

        PaymentMethods::ValidateService.new(result, payment_method: payment_method_params).valid?
      end

      def deliver_webhook
        SendWebhookJob.perform_later(
          "invoice.payment_failure", invoice, error_details: {code: "customer_must_have_payment_provider"}
        )
      end
    end
  end
end
