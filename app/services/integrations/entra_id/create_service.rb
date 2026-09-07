# frozen_string_literal: true

module Integrations
  module EntraId
    class CreateService < Integrations::CreateService
      def call(**args) # rubocop:disable Cops/ServiceCallCop
        organization = Organization.find_by(id: args[:organization_id])

        unless organization.entra_id_enabled?
          return result.not_allowed_failure!(code: "premium_integration_missing")
        end

        integration = Integrations::EntraIdIntegration.new(
          organization:,
          name: "Entra ID Integration",
          code: "entra_id",
          client_id: args[:client_id],
          client_secret: args[:client_secret],
          domain: args[:domain],
          tenant_id: args[:tenant_id],
          host: args[:host]
        )

        integration.save!
        organization.enable_entra_id_authentication!

        result.integration = integration
        result
      rescue ActiveRecord::RecordInvalid => e
        result.record_validation_failure!(record: e.record)
      end
    end
  end
end
