# frozen_string_literal: true

module Integrations
  module Quickbooks
    class UpdateService < Integrations::UpdateService
      def initialize(integration:, params:)
        @integration = integration
        @params = params

        super
      end

      # connection_id, sandbox and realm_id are never updated: changing sandbox
      # would switch the Nango provider config while the connection stays the same.
      def call
        return result.not_found_failure!(resource: "integration") unless integration.is_a?(Integrations::QuickbooksIntegration)

        unless integration.organization.quickbooks_enabled?
          return result.forbidden_failure!(code: "premium_integration_missing")
        end

        # Reloaded under a row lock: the settings are one column, and a connection check may have flagged
        # the integration since it was loaded.
        integration.with_lock do
          integration.name = params[:name] if params.key?(:name)
          integration.code = params[:code] if params.key?(:code)
          integration.sync_credit_notes = cast_boolean(params[:sync_credit_notes]) if params.key?(:sync_credit_notes)
          integration.sync_invoices = cast_boolean(params[:sync_invoices]) if params.key?(:sync_invoices)
          integration.sync_payments = cast_boolean(params[:sync_payments]) if params.key?(:sync_payments)

          integration.save!
        end

        result.integration = integration
        result
      rescue ActiveRecord::RecordInvalid => e
        result.record_validation_failure!(record: e.record)
      rescue ActiveRecord::RecordNotUnique => e
        unique_index_failure!(e, Integrations::QuickbooksIntegration::UNIQUE_INDEXES)
      end

      private

      attr_reader :integration, :params

      # Same cast as on create: an explicit null stores false.
      def cast_boolean(value)
        ActiveModel::Type::Boolean.new.cast(value) || false
      end
    end
  end
end
