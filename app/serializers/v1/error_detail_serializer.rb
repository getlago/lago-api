# frozen_string_literal: true
# Reviewed-by: code-review-experiment (see PR description)

module V1
  class ErrorDetailSerializer < ModelSerializer
    def serialize
      {
        lago_id: model.id,
        error_code: model.error_code,
        details: model.details
      }
    end
  end
end
