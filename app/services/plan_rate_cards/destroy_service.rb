# frozen_string_literal: true

module PlanRateCards
  # Removes a rate card from a plan. A plan with subscriptions is immutable:
  # pricing changes go through a new plan and a subscription migration.
  class DestroyService < BaseService
    Result = BaseResult[:plan_rate_card]

    def initialize(plan_rate_card:)
      @plan_rate_card = plan_rate_card
      super
    end

    def call
      return result.not_found_failure!(resource: "plan_rate_card") unless plan_rate_card

      if plan_rate_card.plan.attached_to_subscriptions?
        return result.single_validation_failure!(field: :plan, error_code: "plan_locked")
      end

      ActiveRecord::Base.transaction do
        phases = plan_rate_card.rate_phases.to_a
        RateOverride.where(id: phases.filter_map(&:rate_override_id)).discard_all!
        plan_rate_card.rate_phases.discard_all!
        plan_rate_card.discard!
      end

      result.plan_rate_card = plan_rate_card
      result
    end

    private

    attr_reader :plan_rate_card
  end
end
