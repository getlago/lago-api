# frozen_string_literal: true

module V2
  class TaxSerializer < ModelSerializer
    def serialize
      {
        lago_id: model.id,
        name: model.name,
        code: model.code,
        rate: model.rate,
        description: model.description,
        created_at: model.created_at.iso8601,
        updated_at: model.updated_at.iso8601,
        deleted_at: model.deleted_at&.iso8601
      }
    end
  end
end
