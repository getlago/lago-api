# frozen_string_literal: true

class CatalogPlansQuery < BaseQuery
  Result = BaseResult[:catalog_plans]

  class Filters < BaseFilters[:product_ids, :product_filter_ids, :product_category_ids, :rate_card_ids]
    def rate_card_scoped?
      [product_ids, product_filter_ids, product_category_ids, rate_card_ids].any?(&:present?)
    end
  end

  def call
    catalog_plans = base_scope.result
    catalog_plans = with_rate_cards(catalog_plans) if filters.rate_card_scoped?
    catalog_plans = apply_consistent_ordering(catalog_plans)
    # The serializer reads applied_rate_cards.size per plan; preload so the
    # collection resolves the counts in one query instead of one per plan.
    catalog_plans = catalog_plans.includes(:applied_rate_cards)

    result.catalog_plans = paginate(catalog_plans)
    result
  end

  private

  def base_scope
    CatalogPlan.where(organization:).ransack(search_params)
  end

  def search_params
    return if search_term.blank?

    {
      m: "or",
      name_cont: search_term,
      code_cont: search_term
    }
  end

  # A plan matches when one of its rate cards matches every given filter.
  def with_rate_cards(scope)
    scope.where(id: PlanRateCard.where(organization:, rate_card_id: matching_rate_cards.select(:id)).select(:catalog_plan_id))
  end

  def matching_rate_cards
    rate_cards = RateCard.where(organization:)
    rate_cards = rate_cards.where(id: filters.rate_card_ids) if filters.rate_card_ids.present?
    rate_cards = rate_cards.where(product_id: filters.product_ids) if filters.product_ids.present?
    rate_cards = rate_cards.where(product_filter_id: filters.product_filter_ids) if filters.product_filter_ids.present?

    if filters.product_category_ids.present?
      rate_cards = rate_cards.where(product_id: organization.products.in_categories(filters.product_category_ids).select(:id))
    end

    rate_cards
  end
end
