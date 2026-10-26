# frozen_string_literal: true

module PlanRateCards
  # Removes a rate card from a plan. A plan with contracts is immutable:
  # pricing changes go through a new plan and a contract migration.
  class DestroyService < BaseService
    Result = BaseResult[:plan_rate_card]

    activity_loggable(
      action: "plan_rate_card.deleted",
      record: -> { plan_rate_card },
      condition: -> { emit_events }
    )

    def initialize(plan_rate_card:, emit_events: true)
      @plan_rate_card = plan_rate_card
      @emit_events = emit_events
      super
    end

    def call
      return result.not_found_failure!(resource: "applied_rate_card") unless plan_rate_card

      plan_rate_card.with_lock do
        return result.not_found_failure!(resource: "applied_rate_card") if plan_rate_card.discarded?

        if plan_rate_card.catalog_plan.attached_to_contracts?
          return result.single_validation_failure!(field: :plan, error_code: "plan_locked")
        end

        phases = plan_rate_card.rate_phases.to_a
        RateOverride.where(id: phases.filter_map(&:rate_override_id)).discard_all!
        plan_rate_card.rate_phases.discard_all!
        plan_rate_card.discard!
        if emit_events
          SendWebhookJob.perform_after_commit("plan_rate_card.deleted", plan_rate_card)
        end
      end

      result.plan_rate_card = plan_rate_card
      result
    end

    private

    attr_reader :plan_rate_card, :emit_events
  end
end
