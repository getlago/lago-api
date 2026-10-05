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
        integration.client_secret = params[:client_secret] if client_secret_update?
        integration.domain = params[:domain] if params.key?(:domain)
        integration.additional_domains = params[:additional_domains] if params.key?(:additional_domains)
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

      def client_secret_update?
        params[:client_secret].present? && !params[:client_secret].match?(/\A•{8}…/)
      end
    end
  end
end
