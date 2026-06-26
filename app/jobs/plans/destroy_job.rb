# frozen_string_literal: true
# Reviewed-by: code-review-experiment (see PR description)

module Plans
  class DestroyJob < ApplicationJob
    queue_as "default"

    unique :until_executed, on_conflict: :log

    def perform(plan)
      plan.children.each do |children_plan|
        Plans::DestroyService.call!(plan: children_plan)
      end

      Plans::DestroyService.call!(plan:)
    end
  end
end
