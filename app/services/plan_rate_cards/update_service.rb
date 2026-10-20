# frozen_string_literal: true

module PlanRateCards
  # Edits a plan's rate card entry. A plan with contracts is immutable:
  # pricing changes go through a new plan and a contract migration.
  class UpdateService < BaseService
    Result = BaseResult[:plan_rate_card]

    activity_loggable(
      action: "plan_rate_card.updated",
      record: -> { plan_rate_card }
    )

    def initialize(plan_rate_card:, params:)
      @plan_rate_card = plan_rate_card
      @params = params.to_h.with_indifferent_access
      super
    end

    def call
      return result.not_found_failure!(resource: "applied_rate_card") unless plan_rate_card

      plan_rate_card.with_lock do
        return result.not_found_failure!(resource: "applied_rate_card") if plan_rate_card.discarded?

        if plan_rate_card.catalog_plan.attached_to_contracts?
          return result.single_validation_failure!(field: :plan, error_code: "plan_locked")
        end

        plan_rate_card.units = params[:units] if params.key?(:units)
        plan_rate_card.save!

        SendWebhookJob.perform_after_commit("plan_rate_card.updated", plan_rate_card)
      end

      result.plan_rate_card = plan_rate_card
      result
    rescue ActiveRecord::RecordInvalid => e
      result.record_validation_failure!(record: e.record)
    end

    private

    attr_reader :plan_rate_card, :params
  end
end
