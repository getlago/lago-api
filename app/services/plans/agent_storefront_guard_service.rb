# frozen_string_literal: true

module Plans
  class AgentStorefrontGuardService < BaseService
    Result = BaseResult

    def initialize(plan:)
      @plan = plan
      super
    end

    def call
      return result unless plan.sold_by_agent_storefront?

      if X402::PlanEligibility.usage_only?(plan.reload)
        result
      else
        result.not_allowed_failure!(code: "plan_sold_by_agent_storefront")
      end
    end

    private

    attr_reader :plan
  end
end
