# frozen_string_literal: true

module V1
  class UsageAttributionTypeSerializer < ModelSerializer
    def serialize
      {
        lago_id: model.id,
        lago_organization_id: model.organization_id,
        code: model.code,
        name: model.name,
        description: model.description,
        attribution_keys: model.attribution_keys,
        role: model.role,
        lago_parent_id: model.parent_id,
        parent_code: model.parent&.code,
        created_at: model.created_at.iso8601,
        updated_at: model.updated_at.iso8601
      }
    end
  end
end
