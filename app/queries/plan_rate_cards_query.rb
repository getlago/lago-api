# frozen_string_literal: true

class PlanRateCardsQuery < BaseQuery
  Result = BaseResult[:plan_rate_cards]
  Filters = BaseFilters[:plan_id, :plan_code]

  def call
    plan_rate_cards = base_scope
    plan_rate_cards = with_plan(plan_rate_cards) if filters.plan_id.present?
    plan_rate_cards = with_plan_code(plan_rate_cards) if filters.plan_code.present?
    plan_rate_cards = paginate(plan_rate_cards)
    plan_rate_cards = apply_consistent_ordering(plan_rate_cards)

    result.plan_rate_cards = plan_rate_cards
    result
  end

  private

  def base_scope
    PlanRateCard.where(organization:)
  end

  def with_plan(scope)
    scope.where(plan_id: filters.plan_id)
  end

  def with_plan_code(scope)
    scope.joins(:plan).where(plans: {code: filters.plan_code})
  end
end
