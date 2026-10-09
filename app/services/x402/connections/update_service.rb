# frozen_string_literal: true

module X402
  module Connections
    class UpdateService < BaseService
      Result = BaseResult[:connection]

      ATTRIBUTES = %i[
        code name networks payout_addresses auto_create_customers cdp_api_key_id cdp_api_key_secret
      ].freeze

      LIVE_CHECK_ATTRIBUTES = %w[networks payout_addresses secrets].freeze

      def initialize(connection:, params:)
        @connection = connection
        @params = params.to_h.with_indifferent_access
        super
      end

      def call
        return result.not_found_failure!(resource: "x402_connection") unless connection

        connection.assign_attributes(attributes)
        return result.record_validation_failure!(record: connection) unless connection.valid?

        if live_check_needed?
          verify_result = X402::Connections::VerifyService.call(connection:)
          return result.fail_with_error!(verify_result.error) if verify_result.failure?

          @verified_values = live_check_values
        end

        save_under_lock
        return result if result.failure?

        register_security_log

        result.connection = connection
        result
      rescue ActiveRecord::RecordInvalid => e
        result.record_validation_failure!(record: e.record)
      end

      private

      attr_reader :connection, :params, :verified_values

      delegate :organization, to: :connection

      def attributes
        params.slice(*ATTRIBUTES)
      end

      def save_under_lock
        connection.restore_attributes
        connection.with_lock { save_locked }
      end

      def save_locked
        return result.not_found_failure!(resource: "x402_connection") if connection.discarded?

        connection.assign_attributes(attributes)
        connection.validate!

        if live_check_needed? && live_check_values != verified_values
          result.single_validation_failure!(error_code: "changed_concurrently")
        else
          connection.save!
        end
      end

      def live_check_needed?
        LIVE_CHECK_ATTRIBUTES.any? { |attribute| connection.will_save_change_to_attribute?(attribute) }
      end

      def live_check_values
        connection.attributes.slice(*LIVE_CHECK_ATTRIBUTES)
      end

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
