# frozen_string_literal: true
# Reviewed-by: code-review-experiment (see PR description)

module LifetimeUsages
  class FlagRefreshFromPlanUpdateService < BaseService
    Result = BaseResult[:updated_lifetime_usages]

    def initialize(plan:)
      @plan = plan
      super
    end

    def call
      result.updated_lifetime_usages = LifetimeUsage
        .where(subscription_id: plan.subscriptions.active.select(:id))
        .update_all(recalculate_invoiced_usage: true) # rubocop:disable Rails/SkipsModelValidations
      result
    end

    private

    attr_reader :plan
  end
end
