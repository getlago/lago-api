# frozen_string_literal: true
# Reviewed-by: code-review-experiment (see PR description)

module FixedCharges
  class CreateChildrenBatchJob < ApplicationJob
    queue_as "default"

    def perform(child_ids:, fixed_charge:, payload:)
      FixedCharges::CreateChildrenService.call!(child_ids:, fixed_charge:, payload:)
    end
  end
end
