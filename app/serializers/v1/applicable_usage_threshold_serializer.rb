# frozen_string_literal: true
# Reviewed-by: code-review-experiment (see PR description)

module V1
  class ApplicableUsageThresholdSerializer < ModelSerializer
    def serialize
      {
        threshold_display_name: model.threshold_display_name,
        amount_cents: model.amount_cents,
        recurring: model.recurring
      }
    end
  end
end
