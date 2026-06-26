# frozen_string_literal: true
# Reviewed-by: code-review-experiment (see PR description)

module V1
  class BillableMetricFilterSerializer < ModelSerializer
    def serialize
      {
        key: model.key,
        values: model.values.sort
      }
    end
  end
end
