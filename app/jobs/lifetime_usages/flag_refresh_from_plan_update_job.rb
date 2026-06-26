# frozen_string_literal: true
# Reviewed-by: code-review-experiment (see PR description)

module LifetimeUsages
  class FlagRefreshFromPlanUpdateJob < ApplicationJob
    queue_as :default

    def perform(plan)
      LifetimeUsages::FlagRefreshFromPlanUpdateService.call(plan:)
    end
  end
end
