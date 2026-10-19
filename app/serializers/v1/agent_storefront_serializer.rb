# frozen_string_literal: true

module V1
  class AgentStorefrontSerializer < ModelSerializer
    def serialize
      {
        lago_id: model.id,
        lago_organization_id: model.organization_id,
        code: model.code,
        name: model.name,
        payment_provider_code: model.payment_provider_code,
        resource_endpoint: model.resource_endpoint,
        resource_instructions: model.resource_instructions,
        scope: model.scope,
        created_at: model.created_at.iso8601,
        updated_at: model.updated_at.iso8601
      }
    end
  end
end
