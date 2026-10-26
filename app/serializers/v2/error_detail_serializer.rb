# frozen_string_literal: true

module V2
  class ErrorDetailSerializer < ModelSerializer
    def serialize
      {
        lago_id: model.id,
        error_code: model.error_code,
        details: model.details,
        created_at: format_time(model.created_at),
        updated_at: format_time(model.updated_at),
        deleted_at: format_time(model.deleted_at)
      }
    end
  end
end
