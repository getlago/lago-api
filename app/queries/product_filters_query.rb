# frozen_string_literal: true

class ProductFiltersQuery < BaseQuery
  Result = BaseResult[:product_filters]
  Filters = BaseFilters[:product_id, :product_category_ids, :without_product_category]

  def call
    product_filters = base_scope.result.includes(values: :billable_metric_filter)
    product_filters = paginate(product_filters)
    product_filters = apply_consistent_ordering(product_filters)

    product_filters = with_product(product_filters) if filters.product_id.present?
    if filters.product_category_ids.present? || filters.without_product_category.present?
      product_filters = with_product_category(product_filters)
    end

    result.product_filters = product_filters
    result
  end

  private

  def base_scope
    ProductFilter.where(organization:).ransack(search_params)
  end

  def search_params
    return if search_term.blank?

    {
      m: "or",
      name_cont: search_term,
      code_cont: search_term
    }
  end

  def with_product(scope)
    scope.where(product_id: filters.product_id)
  end

  # The product_category dimension is a multi-select: chosen product_categories OR "no product_category".
  # A filter's product_category is its parent item's product_category.
  def with_product_category(scope)
    scope = scope.joins(:product)
    if filters.product_category_ids.present? && filters.without_product_category.present?
      scope.where(products: {product_category_id: filters.product_category_ids})
        .or(scope.where(products: {product_category_id: nil}))
    elsif filters.without_product_category.present?
      scope.where(products: {product_category_id: nil})
    else
      scope.where(products: {product_category_id: filters.product_category_ids})
    end
  end
end
