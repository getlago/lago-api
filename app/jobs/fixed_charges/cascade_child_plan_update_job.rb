# frozen_string_literal: true
# Reviewed-by: code-review-experiment (see PR description)

module FixedCharges
  class CascadeChildPlanUpdateJob < ApplicationJob
    queue_as :default

    def perform(plan:, cascade_fixed_charges_payload:, timestamp:)
      FixedCharges::CascadeChildPlanUpdateService.call!(
        plan:,
        cascade_fixed_charges_payload:,
        timestamp:
      )
    end
  end
end
