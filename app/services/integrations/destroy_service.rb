# frozen_string_literal: true

module Integrations
  class DestroyService < BaseService
    def destroy(id:)
      integration = Integrations::BaseIntegration.find_by(
        id:,
        organization_id: result.user.organization_ids,
      )
      return result.not_found_failure!(resource: 'integration') unless integration

      integration.destroy!

      result.integration = integration
      result
    end
  end
end
