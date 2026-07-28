# frozen_string_literal: true

require "openssl"

module PaymentProviders
  module Paystack
    class ValidateIncomingWebhookService < BaseService
      def initialize(payload:, signature:, payment_provider:)
        @payload = payload
        @signature = signature
        @payment_provider = payment_provider

        super
      end

      def call
        return result.service_failure!(code: "webhook_error", message: "Missing signature") if signature.blank?

        unless signature_valid?
          return result.service_failure!(code: "webhook_error", message: "Invalid signature")
        end

        return result.service_failure!(code: "webhook_error", message: "Invalid payload") unless payload_json?

        result
      end

      private

      attr_reader :payload, :signature, :payment_provider

      def calculated_signature
        OpenSSL::HMAC.hexdigest("SHA512", payment_provider.secret_key, payload)
      end

      def signature_valid?
        ActiveSupport::SecurityUtils.secure_compare(calculated_signature, signature)
      rescue ArgumentError
        false
      end

      def payload_json?
        JSON.parse(payload)
        true
      rescue JSON::ParserError
        false
      end
    end
  end
end
