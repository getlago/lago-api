# frozen_string_literal: true

module Plans
  class DestroyJob < ApplicationJob
    queue_as "default"

    unique :until_executed, on_conflict: :log

    def perform(plan)
      plan.children.each do |children_plan|
        children_result = Plans::DestroyService.call(plan: children_plan)
        children_result.raise_if_error!
      end

      result = Plans::DestroyService.call(plan:)
      result.raise_if_error!
    end
  end
end
