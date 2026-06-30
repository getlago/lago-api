# frozen_string_literal: true

class PlanProductItemsQuery < BaseQuery
  Result = BaseResult[:plan_product_items]
  Filters = BaseFilters[:plan_id]

  def call
    plan_product_items = base_scope
    plan_product_items = with_plan(plan_product_items) if filters.plan_id.present?
    plan_product_items = paginate(plan_product_items)
    plan_product_items = apply_consistent_ordering(plan_product_items)

    result.plan_product_items = plan_product_items
    result
  end

  private

  def base_scope
    PlanProductItem.where(organization:)
  end

  def with_plan(scope)
    scope.where(plan_id: filters.plan_id)
  end
end
