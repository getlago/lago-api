# frozen_string_literal: true

module Integrations
  module Quickbooks
    # NOTE: No PerformSyncJob is enqueued: the aggregator sync has no QuickBooks branch yet.
    class CreateService < Integrations::CreateService
      def call(**args) # rubocop:disable Cops/ServiceCallCop
        organization = Organization.find_by(id: args[:organization_id])

        unless organization.quickbooks_enabled?
          return result.forbidden_failure!(code: "premium_integration_missing")
        end

        integration = Integrations::QuickbooksIntegration.new(
          organization:,
          name: args[:name],
          code: args[:code],
          connection_id: args[:connection_id],
          sandbox: cast_boolean(args[:sandbox]),
          sync_credit_notes: cast_boolean(args[:sync_credit_notes]),
          sync_invoices: cast_boolean(args[:sync_invoices]),
          sync_payments: cast_boolean(args[:sync_payments])
        )

        # Refuse an invalid name, code or connection_id before calling Nango.
        unless integration.valid?
          return result.record_validation_failure!(record: integration)
        end

        lookup = Integrations::Aggregator::ConnectionService.call(integration:)
        return result.fail_with_error!(lookup.error) unless lookup.success?

        integration.realm_id = lookup.realm_id
        integration.save!

        result.integration = integration
        result
      rescue ActiveRecord::RecordInvalid => e
        result.record_validation_failure!(record: e.record)
      end

      private

      def cast_boolean(value)
        ActiveModel::Type::Boolean.new.cast(value) || false
      end
    end
  end
end
