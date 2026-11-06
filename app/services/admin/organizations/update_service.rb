# frozen_string_literal: true

module Admin
  module Organizations
    class UpdateService < ::BaseService
      Result = BaseResult[:organization]

      def initialize(organization:, params:)
        @organization = organization
        @params = params

        super
      end

      def call
        return result.not_found_failure!(resource: "organization") unless organization

        ActiveRecord::Base.transaction do
          ::Organizations::SandboxLockService.call!(organization:, allow_sandbox: true)
          if organization.sandbox? && params.key?(:premium_integrations)
            result.not_allowed_failure!(code: "sandbox_managed_by_production").raise_if_error!
          end

          organization.name = params[:name] if params.key?(:name)
          organization.premium_integrations = params[:premium_integrations] if params.key?(:premium_integrations)
          organization.save!

          if organization.saved_change_to_premium_integrations?
            ::Organizations::SyncSandboxSettingsService.call!(organization:)
          end
        end
        ApiKeys::CacheService.expire_all_cache(organization)

        result.organization = organization
        result
      rescue ActiveRecord::RecordInvalid => e
        result.record_validation_failure!(record: e.record)
      rescue BaseService::FailedResult => e
        result.fail_with_error!(e)
      end

      private

      attr_reader :organization, :params
    end
  end
end
