# frozen_string_literal: true

module PaymentProviders
  module Paystack
    class HandleIncomingWebhookService < BaseService
      Result = BaseResult[:event]

      def initialize(inbound_webhook:)
        @inbound_webhook = inbound_webhook

        super
      end

      def call
        payment_provider_result = PaymentProviders::FindService.call(
          organization_id: inbound_webhook.organization_id,
          code: inbound_webhook.code,
          payment_provider_type: "paystack"
        )

        return handle_payment_provider_failure(payment_provider_result) unless payment_provider_result.success?

        PaymentProviders::Paystack::HandleEventJob.perform_later(
          inbound_webhook.organization_id,
          payment_provider_result.payment_provider.id,
          inbound_webhook.payload
        )

        result.event = inbound_webhook.payload
        result
      end

      private

      attr_reader :inbound_webhook

      def handle_payment_provider_failure(payment_provider_result)
        return payment_provider_result unless payment_provider_result.error.is_a?(BaseService::ServiceFailure)

        result.service_failure!(code: "webhook_error", message: payment_provider_result.error.error_message)
      end
    end
  end
end
