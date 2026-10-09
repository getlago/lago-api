# frozen_string_literal: true

module X402
  module Connections
    class VerifyPayoutAddressService < BaseService
      Result = BaseResult

      def initialize(connection:)
        @connection = connection
        super
      end

      def call
        errors = []

        in_use_families.each do |family|
          lookup = client.lookup(family:, address: connection.payout_addresses.fetch(family.to_s))

          case lookup.outcome
          when :not_found
            errors << "#{family}_not_in_cdp_project"
          when :invalid
            errors << "#{family}_rejected_by_cdp"
          when :forbidden
            return result.single_validation_failure!(field: :cdp_api_key, error_code: "missing_account_read_permission")
          when :rate_limited, :unavailable
            return third_party_failure(lookup)
          end
        end

        if errors.any?
          result.validation_failure!(errors: {payout_addresses: errors})
        else
          result
        end
      end

      private

      attr_reader :connection

      def in_use_families
        connection.networks.map { |network| X402::Network.family_of_network(network) }.uniq
      end

      def client
        @client ||= X402::Cdp::AccountsClient.new(api_key_id: connection.cdp_api_key_id, api_key_secret: connection.cdp_api_key_secret)
      end

      def third_party_failure(lookup)
        reason = (lookup.outcome == :rate_limited) ? "rate_limit_error" : "unavailable_error"

        result.third_party_failure!(
          third_party: connection.facilitator,
          error_code: reason,
          error_message: "#{reason}: #{lookup.family} account lookup answered #{lookup.http_status || "nothing"}"
        )
      end
    end
  end
end
