# frozen_string_literal: true

module V2
  class ErrorDetailSerializer < ModelSerializer
    def serialize
      {
        lago_id: model.id,
        error_code: model.error_code,
        details: model.details,
        created_at: model.created_at.iso8601,
        updated_at: model.updated_at.iso8601,
        deleted_at: model.deleted_at&.iso8601
      }
    end
  end
end
