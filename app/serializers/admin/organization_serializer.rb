# frozen_string_literal: true

module Admin
  class OrganizationSerializer < ModelSerializer
    def serialize
      {
        id: model.id,
        name: model.name,
        document_numbering: model.document_numbering,
        premium_integrations: model.premium_integrations,
        self_serve: model.self_serve,
        environment: model.environment,
        production_organization_id: model.production_organization_id,
        sandbox_organization_id: model.sandbox_organization&.id,
        created_at: model.created_at.iso8601,
        updated_at: model.updated_at.iso8601
      }
    end
  end
end
