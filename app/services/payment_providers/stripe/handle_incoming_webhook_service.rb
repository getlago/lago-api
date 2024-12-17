# frozen_string_literal: true

module PaymentProviders
  module Stripe
    class HandleIncomingWebhookService < BaseService
      extend Forwardable

      def initialize(inbound_webhook:)
        @inbound_webhook = inbound_webhook

        super
      end

      def call
        payment_provider_result = PaymentProviders::FindService.call(
          organization_id:,
          code:,
          payment_provider_type: "stripe"
        )

        return payment_provider_result unless payment_provider_result.success?

        event = ::Stripe::Webhook.construct_event(
          payload,
          signature,
          payment_provider_result.payment_provider&.webhook_secret
        )

        PaymentProviders::Stripe::HandleEventJob.perform_later(
          organization: payment_provider_result.payment_provider.organization,
          event: event.to_json
        )

        result.event = event
        result
      rescue JSON::ParserError
        result.service_failure!(code: "webhook_error", message: "Invalid payload")
      rescue ::Stripe::SignatureVerificationError
        result.service_failure!(code: "webhook_error", message: "Invalid signature")
      end

      private

      def_delegators :@inbound_webhook, :code, :organization_id, :payload, :signature
    end
  end
end
