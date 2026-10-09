# frozen_string_literal: true

module X402
  module Connections
    class VerifyService < BaseService
      Result = BaseResult

      def initialize(connection:)
        @connection = connection
        super
      end

      def call
        supported = X402::Facilitator::Client.for(connection).supported

        if connection.networks.all? { |network| supported.supports?(network:) }
          verify_payout_addresses
        else
          result.single_validation_failure!(field: :networks, error_code: "unsupported_network")
        end
      rescue X402::Facilitator::CredentialError => e
        result.single_validation_failure!(field: :cdp_api_key, error_code: (e.http_status == 402) ? "payment_method_required" : "invalid_credentials")
      rescue X402::Cdp::Jwt::InvalidKeyError
        result.single_validation_failure!(field: :cdp_api_key, error_code: "invalid_credentials")
      rescue X402::Facilitator::RateLimitError, X402::Facilitator::UnavailableError => e
        reason = e.class.name.demodulize.underscore
        result.third_party_failure!(third_party: connection.facilitator, error_code: reason, error_message: "#{reason}: #{e.message}")
      end

      private

      attr_reader :connection

      def verify_payout_addresses
        payout_result = X402::Connections::VerifyPayoutAddressService.call(connection:)

        if payout_result.success?
          result
        else
          result.fail_with_error!(payout_result.error)
        end
      end
    end
  end
end
