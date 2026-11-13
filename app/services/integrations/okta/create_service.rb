# frozen_string_literal: true

module Integrations
  module Okta
    class CreateService < Integrations::CreateService
      def call(**args) # rubocop:disable Cops/ServiceCallCop
        organization = Organization.find_by(id: args[:organization_id])

        unless organization.okta_enabled?
          return result.forbidden_failure!(code: "premium_integration_missing")
        end

        integration = Integrations::OktaIntegration.new(
          organization:,
          name: "Okta Integration",
          code: "okta",
          client_id: args[:client_id],
          client_secret: args[:client_secret],
          domain: args[:domain],
          organization_name: args[:organization_name],
          host: args[:host]
        )

        ActiveRecord::Base.transaction do
          # A sandbox has no SSO integration of its own: it accepts the sessions of its production's.
          ::Organizations::SandboxLockService.call!(organization:)
          integration.save!
          organization.enable_okta_authentication!
          ::Organizations::SyncSandboxSettingsService.call!(organization:)
        end

        result.integration = integration
        result
      rescue ActiveRecord::RecordInvalid => e
        result.record_validation_failure!(record: e.record)
      rescue BaseService::FailedResult => e
        result.fail_with_error!(e)
      end
    end
  end
end
