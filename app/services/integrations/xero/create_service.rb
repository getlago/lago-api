# frozen_string_literal: true

module Integrations
  module Xero
    class CreateService < BaseService
      def call(**args)
        organization = Organization.find_by(id: args[:organization_id])

        unless organization.premium_integrations.include?('xero')
          return result.not_allowed_failure!(code: 'premium_integration_missing')
        end

        integration = Integrations::XeroIntegration.new(
          organization:,
          name: args[:name],
          code: args[:code],
          connection_id: args[:connection_id]
        )

        integration.save!

        if integration.type == 'Integrations::XeroIntegration'
          Integrations::Aggregator::PerformSyncJob.set(wait: 2.seconds).perform_later(integration:)
        end

        result.integration = integration
        result
      rescue ActiveRecord::RecordInvalid => e
        result.record_validation_failure!(record: e.record)
      end
    end
  end
end
