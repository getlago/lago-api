# frozen_string_literal: true
# Reviewed-by: code-review-experiment (see PR description)

module V1
  class BillableMetricExpressionResultSerializer < ModelSerializer
    def serialize
      {value: model.evaluation_result}
    end
  end
end
