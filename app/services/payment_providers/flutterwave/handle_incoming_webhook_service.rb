# frozen_string_literal: true

module PaymentProviders
  module Flutterwave
    class HandleIncomingWebhookService < BaseService
      Result = BaseResult[:event]
      def initialize(organization_id:, body:, signature:, code: nil)
        @organization_id = organization_id
        @body = body
        @signature = signature
        @code = code

        super
      end

      def call
        organization = Organization.find_by(id: organization_id)

        payment_provider_result = PaymentProviders::FindService.call(
          organization_id:,
          code:,
          payment_provider_type: "flutterwave"
        )

        return payment_provider_result unless payment_provider_result.success?

        webhook_secret = payment_provider_result.payment_provider.webhook_secret
        return result.service_failure!(code: "webhook_error", message: "Missing webhook secret") if webhook_secret.blank?

        expected_signature = Digest::SHA256.hexdigest(webhook_secret)

        unless expected_signature == signature
          return result.service_failure!(code: "webhook_error", message: "Invalid signature")
        end

        PaymentProviders::Flutterwave::HandleEventJob.perform_later(organization:, event: body)

        result.event = body
        result
      end

      private

      attr_reader :organization_id, :body, :signature, :code
    end
  end
end
