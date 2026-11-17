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

        integration.name = params[:name] if params.key?(:name)
        integration.code = params[:code] if params.key?(:code)
        integration.sync_credit_notes = params[:sync_credit_notes] if params.key?(:sync_credit_notes)
        integration.sync_invoices = params[:sync_invoices] if params.key?(:sync_invoices)
        integration.sync_payments = params[:sync_payments] if params.key?(:sync_payments)

        integration.save!

        result.integration = integration
        result
      rescue ActiveRecord::RecordInvalid => e
        result.record_validation_failure!(record: e.record)
      end

      private

      attr_reader :integration, :params
    end
  end
end
