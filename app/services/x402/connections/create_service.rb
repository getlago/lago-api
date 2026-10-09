# frozen_string_literal: true

module X402
  module Connections
    class CreateService < BaseService
      Result = BaseResult[:connection]

      ATTRIBUTES = %i[
        code name facilitator asset networks payout_addresses auto_create_customers cdp_api_key_id cdp_api_key_secret
      ].freeze

      def initialize(organization:, params:)
        @organization = organization
        @params = params.to_h.with_indifferent_access
        super
      end

      def call
        connection = organization.x402_connections.new(params.slice(*ATTRIBUTES))
        return result.record_validation_failure!(record: connection) unless connection.valid?

        verify_result = X402::Connections::VerifyService.call(connection:)
        return result.fail_with_error!(verify_result.error) if verify_result.failure?

        connection.save!

        register_security_log(connection)

        result.connection = connection
        result
      rescue ActiveRecord::RecordInvalid => e
        result.record_validation_failure!(record: e.record)
      end

      private

      attr_reader :organization, :params

      def register_security_log(connection)
        Utils::SecurityLog.produce(
          organization:,
          log_type: "integration",
          log_event: "integration.created",
          resources: {integration_name: connection.name, integration_type: "x402"}
        )
      end
    end
  end
end
