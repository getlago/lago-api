# frozen_string_literal: true

module Integrations
  module EntraId
    class UpdateService < Integrations::UpdateService
      def initialize(integration:, params:)
        @integration = integration
        @params = params

        super
      end

      def call
        return result.not_found_failure!(resource: "integration") unless integration

        unless integration.organization.entra_id_enabled?
          return result.not_allowed_failure!(code: "premium_integration_missing")
        end

        integration.client_id = params[:client_id] if params.key?(:client_id)
        integration.client_secret = params[:client_secret] if params.key?(:client_secret)
        integration.domain = params[:domain] if params.key?(:domain)
        integration.tenant_id = params[:tenant_id] if params.key?(:tenant_id)
        integration.host = params[:host] if params.key?(:host)

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
