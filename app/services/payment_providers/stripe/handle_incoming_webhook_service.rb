# frozen_string_literal: true

module PaymentProviders
  module Stripe
    class HandleIncomingWebhookService < BaseService
      def initialize(organization_id:, body:, signature:, code: nil)
        @organization_id = organization_id
        @body = body
        @signature = signature
        @code = code

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
          body,
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

      attr_reader :organization_id, :body, :signature, :code
    end
  end
end
