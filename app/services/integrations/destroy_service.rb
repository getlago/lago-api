# frozen_string_literal: true

module Integrations
  class DestroyService < BaseService
    Result = BaseResult[:integration]

    def initialize(integration:)
      @integration = integration

      super
    end

    def call
      return result.not_found_failure!(resource: "integration") unless integration

      ActiveRecord::Base.transaction do
        if integration.is_a?(Integrations::AgentStorefrontIntegration)
          # Waits for the enrollments in progress, which lock the storefront for share.
          integration.lock!
          if integration.enrolled_agents?
            result.not_allowed_failure!(code: "agent_storefront_has_enrolled_agents").raise_if_error!
          end
        end

        integration.destroy!
      end

      result.integration = integration
      register_security_log(integration)
      result
    rescue BaseService::FailedResult
      result
    end

    private

    attr_reader :integration

    def register_security_log(integration)
      Utils::SecurityLog.produce(
        organization: integration.organization,
        log_type: "integration",
        log_event: "integration.deleted",
        resources: {integration_name: integration.name, integration_type: integration.provider_key}
      )
    end
  end
end
