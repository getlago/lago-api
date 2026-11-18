# frozen_string_literal: true

module Integrations
  module Okta
    class UpdateService < Integrations::UpdateService
      def initialize(integration:, params:)
        @integration = integration
        @params = params

        super
      end

      def call
        return result.not_found_failure!(resource: "integration") unless integration

        ActiveRecord::Base.transaction do
          # A sandbox trusts its production's SSO: an integration it kept from before its link cannot be repointed.
          organization = ::Organizations::SandboxLockService.call!(organization: integration.organization).organization
          next result.forbidden_failure!(code: "premium_integration_missing") unless organization.okta_enabled?

          update_integration!
          result.integration = integration
        end

        result
      rescue ActiveRecord::RecordInvalid => e
        result.record_validation_failure!(record: e.record)
      rescue BaseService::FailedResult => e
        result.fail_with_error!(e)
      end

      private

      attr_reader :integration, :params

      def update_integration!
        integration.client_id = params[:client_id] if params.key?(:client_id)
        integration.client_secret = params[:client_secret] if client_secret_update?
        integration.domain = params[:domain] if params.key?(:domain)
        integration.organization_name = params[:organization_name] if params.key?(:organization_name)
        integration.host = params[:host] if params.key?(:host)

        integration.save!
      end

      def client_secret_update?
        params[:client_secret].present? && !params[:client_secret].match?(/\A•{8}…/)
      end
    end
  end
end
