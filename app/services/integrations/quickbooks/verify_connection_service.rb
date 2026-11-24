# frozen_string_literal: true

module Integrations
  module Quickbooks
    # Checks after a re-authentication that the Nango connection still points at the stored company.
    # realm_id is never written: a different company flags the integration, which blocks its syncs.
    class VerifyConnectionService < BaseService
      Result = BaseResult[:integration]

      def initialize(integration:)
        @integration = integration

        super
      end

      def call
        return result.not_found_failure!(resource: "integration") unless integration.is_a?(Integrations::QuickbooksIntegration)

        unless integration.organization.quickbooks_enabled?
          return result.forbidden_failure!(code: "premium_integration_missing")
        end

        lookup = Integrations::Aggregator::ConnectionService.call(integration:)
        return result.fail_with_error!(lookup.error) unless lookup.success?

        if same_realm?(lookup.realm_id)
          store_mismatch(false)

          result.integration = integration
          result
        else
          store_mismatch(true)

          result.not_allowed_failure!(code: "realm_id_changed")
        end
      rescue ActiveRecord::RecordInvalid => e
        result.record_validation_failure!(record: e.record)
      rescue ActiveRecord::RecordNotUnique => e
        unique_index_failure!(e, Integrations::QuickbooksIntegration::UNIQUE_INDEXES)
      end

      private

      attr_reader :integration

      # A blank stored realm never matches: the found company cannot be confirmed.
      def same_realm?(found_realm_id)
        integration.realm_id.present? && found_realm_id == integration.realm_id.to_s
      end

      # Writes only on a change, so a routine check adds no version and keeps updated_at.
      def store_mismatch(value)
        if integration.realm_id_mismatch? != value
          integration.realm_id_mismatch = value
          integration.save!
        end
      end
    end
  end
end
