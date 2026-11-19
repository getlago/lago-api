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

        ActiveRecord::Base.transaction do
          # Waits for an agent's first payment in progress, which locks the storefront for share while it attaches
          # the agent's Stripe customer to the current connection.
          integration.lock!

          # The agents' Stripe customers live on the connection they first paid through, and outlive their subscriptions.
          if connection_change? && integration.agents_with_stripe_customer?
            result.single_validation_failure!(field: :payment_provider_code, error_code: "agent_storefront_has_enrolled_agents").raise_if_error!
          end

          integration.name = params[:name] if params.key?(:name)
          integration.code = params[:code] if params.key?(:code)
          integration.payment_provider_code = params[:payment_provider_code] if params.key?(:payment_provider_code)
          integration.resource_endpoint = params[:resource_endpoint] if params.key?(:resource_endpoint)
          integration.resource_instructions = params[:resource_instructions] if params.key?(:resource_instructions)
          integration.plans = params[:plans] if params.key?(:plans)

          integration.save!
        end

        result.integration = integration
        result
      rescue BaseService::FailedResult => e
        result.fail_with_error!(e)
      rescue ActiveRecord::RecordInvalid => e
        result.record_validation_failure!(record: e.record)
      rescue ActiveRecord::RecordNotUnique => e
        unique_index_failure!(e, "index_integrations_on_code_and_organization_id" => :code)
      end

      private

      attr_reader :integration, :params

      def connection_change?
        params.key?(:payment_provider_code) && params[:payment_provider_code] != integration.payment_provider_code
      end
    end
  end
end
