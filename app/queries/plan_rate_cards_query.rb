# frozen_string_literal: true

class PlanRateCardsQuery < BaseQuery
  include RateCardCategoryOrdering
  include RateCardListFiltering

  Result = BaseResult[:plan_rate_cards]
  Filters = BaseFilters[:plan_id, *RateCardListFiltering::FILTERS]

  def call
    plan_rate_cards = base_scope
    plan_rate_cards = with_plan(plan_rate_cards) if filters.plan_id.present?
    plan_rate_cards = apply_rate_card_filters(plan_rate_cards, phase_parent: :plan_rate_card_id)
    plan_rate_cards = if order == :product_category
      order_by_product_category(plan_rate_cards).order(:id)
    else
      apply_consistent_ordering(plan_rate_cards)
    end

    result.plan_rate_cards = paginate(plan_rate_cards)
    result
  end

  private

  def base_scope
    PlanRateCard.where(organization:)
  end

  def with_plan(scope)
    scope.where(catalog_plan_id: filters.plan_id)
  end
end
