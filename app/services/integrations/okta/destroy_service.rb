# frozen_string_literal: true

module Integrations
  module Okta
    class DestroyService < Integrations::DestroyService
      def call
        return result.not_found_failure!(resource: "integration") unless integration

        ActiveRecord::Base.transaction do
          # A sandbox's login methods follow its production's. The lock reloads the organization, so the check below
          # reads the methods a concurrent change committed.
          organization = ::Organizations::SandboxLockService.call!(organization: integration.organization).organization
          next result.not_allowed_failure!(code: "enabled_authentication_methods_required") unless can_destroy?(organization)

          result = super

          if result.success?
            organization.disable_okta_authentication! if organization.okta_authentication_enabled?
            ::Organizations::SyncSandboxSettingsService.call!(organization:)
          end

          result
        end
      rescue BaseService::FailedResult => e
        result.fail_with_error!(e)
      end

      private

      def can_destroy?(organization)
        (organization.authentication_methods - [Organizations::AuthenticationMethods::OKTA]).size >= 1
      end
    end
  end
end
