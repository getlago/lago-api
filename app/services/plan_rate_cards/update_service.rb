# frozen_string_literal: true

module PlanRateCards
  # Edits a plan's rate card entry. A plan with subscriptions is immutable:
  # pricing changes go through a new plan and a subscription migration.
  class UpdateService < BaseService
    Result = BaseResult[:plan_rate_card]

    def initialize(plan_rate_card:, params:)
      @plan_rate_card = plan_rate_card
      @params = params.to_h.with_indifferent_access
      super
    end

    def call
      return result.not_found_failure!(resource: "plan_rate_card") unless plan_rate_card

      if plan_rate_card.plan.attached_to_subscriptions?
        return result.single_validation_failure!(field: :plan, error_code: "plan_locked")
      end

      plan_rate_card.units = params[:units] if params.key?(:units)
      plan_rate_card.save!

      result.plan_rate_card = plan_rate_card
      result
    rescue ActiveRecord::RecordInvalid => e
      result.record_validation_failure!(record: e.record)
    end

    private

    attr_reader :plan_rate_card, :params
  end
end
