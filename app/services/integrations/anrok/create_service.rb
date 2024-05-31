# frozen_string_literal: true

module Integrations
  module Anrok
    class CreateService < BaseService
      def call(**args)
        organization = Organization.find_by(id: args[:organization_id])

        unless organization.premium_integrations.include?('anrok')
          return result.not_allowed_failure!(code: 'premium_integration_missing')
        end

        integration = Integrations::AnrokIntegration.new(
          organization:,
          name: args[:name],
          code: args[:code],
          api_key: args[:api_key]
        )

        integration.save!

        result.integration = integration
        result
      rescue ActiveRecord::RecordInvalid => e
        result.record_validation_failure!(record: e.record)
      end
    end
  end
end
