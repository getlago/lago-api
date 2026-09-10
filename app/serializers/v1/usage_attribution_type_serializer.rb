# frozen_string_literal: true

module V1
  class UsageAttributionTypeSerializer < ModelSerializer
    def serialize
      {
        lago_id: model.id,
        code: model.code,
        name: model.name,
        attribution_key: model.attribution_key,
        role: model.role,
        parent_code: model.parent&.code,
        created_at: model.created_at.iso8601,
        updated_at: model.updated_at.iso8601
      }
    end
  end
end
