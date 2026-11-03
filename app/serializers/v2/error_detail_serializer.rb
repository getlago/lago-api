# frozen_string_literal: true

module V2
  class ErrorDetailSerializer < ModelSerializer
    timestamps :created_at, :updated_at, :deleted_at

    def serialize
      {
        lago_id: model.id,
        error_code: model.error_code,
        details: model.details
      }
    end
  end
end
