# frozen_string_literal: true

module Integrations
  module Quickbooks
    # NOTE: No PerformSyncJob is enqueued: the aggregator sync has no QuickBooks branch yet.
    class CreateService < Integrations::CreateService
      def initialize(params:)
        @params = params

        super
      end

      def call
        organization = Organization.find_by(id: params[:organization_id])

        unless organization.quickbooks_enabled?
          return result.forbidden_failure!(code: "premium_integration_missing")
        end

        integration = Integrations::QuickbooksIntegration.new(
          organization:,
          name: params[:name],
          code: params[:code],
          connection_id: params[:connection_id],
          sandbox: cast_boolean(params[:sandbox]),
          sync_credit_notes: cast_boolean(params[:sync_credit_notes]),
          sync_invoices: cast_boolean(params[:sync_invoices]),
          sync_payments: cast_boolean(params[:sync_payments])
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
      rescue ActiveRecord::RecordNotUnique => e
        unique_index_failure!(e, Integrations::QuickbooksIntegration::UNIQUE_INDEXES)
      end

      private

      attr_reader :params

      def cast_boolean(value)
        ActiveModel::Type::Boolean.new.cast(value) || false
      end
    end
  end
end
