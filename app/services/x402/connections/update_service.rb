# frozen_string_literal: true

module X402
  module Connections
    class UpdateService < BaseService
      Result = BaseResult[:connection]

      ATTRIBUTES = %i[
        code name networks payout_addresses auto_create_customers cdp_api_key_id cdp_api_key_secret
      ].freeze

      def initialize(connection:, params:)
        @connection = connection
        @params = params.to_h.with_indifferent_access
        super
      end

      def call
        return result.not_found_failure!(resource: "x402_connection") unless connection

        connection.with_lock do
          connection.assign_attributes(params.slice(*ATTRIBUTES))
          connection.save!
        end

        register_security_log

        result.connection = connection
        result
      rescue ActiveRecord::RecordInvalid => e
        result.record_validation_failure!(record: e.record)
      end

      private

      attr_reader :connection, :params

      delegate :organization, to: :connection

      def register_security_log
        diff = connection.previous_changes.except("updated_at", "secrets")
          .to_h.transform_keys(&:to_sym)
          .transform_values { |v| {deleted: v[0], added: v[1]}.compact }

        Utils::SecurityLog.produce(
          organization:,
          log_type: "integration",
          log_event: "integration.updated",
          resources: {integration_name: connection.name, integration_type: "x402", **diff}
        )
      end
    end
  end
end
