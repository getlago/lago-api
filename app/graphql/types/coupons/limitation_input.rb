# frozen_string_literal: true
# Reviewed-by: code-review-experiment (see PR description)

module Types
  module Coupons
    class LimitationInput < BaseInputObject
      argument :billable_metric_ids, [ID], required: false
      argument :plan_ids, [ID], required: false
    end
  end
end
