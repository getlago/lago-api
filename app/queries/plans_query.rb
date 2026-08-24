# frozen_string_literal: true

class PlansQuery < BaseQuery
  Result = BaseResult[:plans]
  Filters = BaseFilters[:with_deleted, :include_pending_deletion, :product_category_id, :pricing_type]

  def call
    plans = base_scope.result
    plans = paginate(plans)
    plans = apply_consistent_ordering(plans)

    plans = exclude_pending_deletion(plans) unless filters.include_pending_deletion
    plans = plans.with_discarded if filters.with_deleted

    result.plans = plans
    result
  end

  private

  def base_scope
    scope = Plan.parents.where(organization:)
    scope = scope.where(pricing_type: filters.pricing_type) if filters.pricing_type.present?
    scope = with_product_category(scope)
    scope.ransack(search_params)
  end

  def with_product_category(scope)
    return scope if filters.product_category_id.blank?

    scope.where(
      id: PlanRateCard
        .joins(rate_card: :product)
        .where(products: {product_category_id: filters.product_category_id})
        .select(:plan_id)
    )
  end

  def search_params
    return if search_term.blank?

    {
      m: "or",
      name_cont: search_term,
      code_cont: search_term
    }
  end

  def exclude_pending_deletion(scope)
    scope.where(pending_deletion: false)
  end
end
