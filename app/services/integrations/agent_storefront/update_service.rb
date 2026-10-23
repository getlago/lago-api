# frozen_string_literal: true

module Integrations
  module AgentStorefront
    class UpdateService < Integrations::UpdateService
      def initialize(integration:, params:)
        @integration = integration
        @params = params

        super
      end

      def call
        return result.not_found_failure!(resource: "integration") unless integration

        unless integration.organization.agent_storefront_enabled?
          return result.not_allowed_failure!(code: "premium_integration_missing")
        end

        integration.name = params[:name] if params.key?(:name)
        integration.code = params[:code] if params.key?(:code)
        integration.payment_provider_code = params[:payment_provider_code] if params.key?(:payment_provider_code)
        integration.resource_endpoint = params[:resource_endpoint] if params.key?(:resource_endpoint)
        integration.resource_instructions = params[:resource_instructions] if params.key?(:resource_instructions)

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
