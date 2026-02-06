# frozen_string_literal: true

module Plans
  class DestroyJob < ApplicationJob
    queue_as "default"

    retry_on Customers::FailedToAcquireLock, attempts: 25, wait: ->(_) { rand(0...16) }

    unique :until_executed, on_conflict: :log

    def perform(plan)
      plan.children.each do |children_plan|
        Plans::DestroyService.call!(plan: children_plan)
      end

      Plans::DestroyService.call!(plan:)
    end
  end
end
