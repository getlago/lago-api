# frozen_string_literal: true

class CatalogPlansQuery < BaseQuery
  Result = BaseResult[:catalog_plans]

  def call
    catalog_plans = base_scope.result
    catalog_plans = paginate(catalog_plans)
    catalog_plans = apply_consistent_ordering(catalog_plans)
    # The serializer reads applied_rate_cards.size per plan; preload so the
    # collection resolves the counts in one query instead of one per plan.
    catalog_plans = catalog_plans.includes(:applied_rate_cards)

    result.catalog_plans = catalog_plans
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
end
