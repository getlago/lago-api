# frozen_string_literal: true

module PaymentProviders
  module Moneyhash
    class ValidateIncomingWebhookService < BaseService
      def initialize(payload:, signature:, payment_provider:)
        @payload = payload
        @signature = signature
        @provider = payment_provider

        super
      end

      def call
        # TODO: Implement moneyhash validation

        result

        # TODO:
        # rescue Moneyhash::SignatureVerificationError
        #   result.service_failure!(code: "webhook_error", message: "Invalid signature")
      end

      private

      attr_reader :payload, :signature, :provider

      def webhook_secret
        # TODO:
      end
    end
  end
end
