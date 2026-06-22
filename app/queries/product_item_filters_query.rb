# frozen_string_literal: true

class ProductItemFiltersQuery < BaseQuery
  Result = BaseResult[:product_item_filters]
  Filters = BaseFilters[:product_item_id]

  def call
    product_item_filters = base_scope.result.includes(values: :billable_metric_filter)
    product_item_filters = paginate(product_item_filters)
    product_item_filters = apply_consistent_ordering(product_item_filters)

    product_item_filters = with_product_item(product_item_filters) if filters.product_item_id.present?

    result.product_item_filters = product_item_filters
    result
  end

  private

  def base_scope
    ProductItemFilter.where(organization:).ransack(search_params)
  end

  def search_params
    return if search_term.blank?

    {
      m: "or",
      name_cont: search_term,
      code_cont: search_term
    }
  end

  def with_product_item(scope)
    scope.where(product_item_id: filters.product_item_id)
  end
end
