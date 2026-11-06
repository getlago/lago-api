# frozen_string_literal: true

module Integrations
  module AgentStorefront
    class CreateService < Integrations::CreateService
      attr_reader :params

      def initialize(params:)
        @params = params

        super
      end

      def call
        organization = Organization.find_by(id: params[:organization_id])

        unless organization.agent_storefront_enabled?
          return result.not_allowed_failure!(code: "premium_integration_missing")
        end

        unless organization.events_targeting_wallets_enabled?
          return result.single_validation_failure!(error_code: "events_targeting_wallets_disabled")
        end

        unless wallet_refresh_available?
          return result.single_validation_failure!(error_code: "wallet_refresh_unavailable")
        end

        integration = Integrations::AgentStorefrontIntegration.new(
          organization:,
          name: params[:name],
          code: params[:code],
          payment_provider_code: params[:payment_provider_code],
          resource_endpoint: params[:resource_endpoint],
          resource_instructions: params[:resource_instructions],
          scope: "#{params[:code]}:use"
        )

        integration.save!

        result.integration = integration
        result
      rescue ActiveRecord::RecordInvalid => e
        result.record_validation_failure!(record: e.record)
      end

      private

      def wallet_refresh_available?
        ENV["LAGO_REDIS_CACHE_URL"].present? && ENV["LAGO_DISABLE_WALLET_REFRESH"] != "true"
      end
    end
  end
end
