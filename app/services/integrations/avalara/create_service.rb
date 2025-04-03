# frozen_string_literal: true

module Integrations
  module Avalara
    class CreateService < BaseService
      def call(**args)
        organization = Organization.find_by(id: args[:organization_id])

        unless organization.avalara_enabled?
          return result.not_allowed_failure!(code: "premium_integration_missing")
        end

        integration = Integrations::AvalaraIntegration.new(
          organization:,
          name: args[:name],
          code: args[:code],
          connection_id: args[:connection_id],
          account_id: args[:account_id],
          license_key: args[:license_key]
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
