# frozen_string_literal: true

module Integrations
  module Okta
    class CreateService < BaseService
      def call(**args)
        organization = Organization.find_by(id: args[:organization_id])

        unless organization.premium_integrations.include?('okta')
          return result.not_allowed_failure!(code: 'premium_integration_missing')
        end

        integration = Integrations::OktaIntegration.new(
          organization:,
          name: 'Okta Integration',
          code: 'okta',
          client_id: args[:client_id],
          client_secret: args[:client_secret],
          domain: args[:domain],
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
