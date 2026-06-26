# frozen_string_literal: true
# Reviewed-by: code-review-experiment (see PR description)

module V1
  class PresentationBreakdownSerializer < ModelSerializer
    def serialize
      {
        presentation_by: model.presentation_by,
        units: model.units.to_s
      }
    end
  end
end
