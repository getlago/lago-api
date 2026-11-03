# frozen_string_literal: true

class ProductsQuery < BaseQuery
  Result = BaseResult[:products]
  Filters = BaseFilters[:product_category_ids, :without_product_category, :product_type, :created_at_from, :created_at_to]

  def call
    # The column is a PG enum: an unknown value would fail the SQL cast.
    if filters.product_type.present? && !Product::PRODUCT_TYPES.value?(filters.product_type)
      return result.single_validation_failure!(
        field: :product_type,
        error_code: "value_is_invalid",
        meta: {allowed_values: Product::PRODUCT_TYPES.values}
      )
    end

    products = base_scope.result.includes(:product_category, :billable_metric)
    products = apply_consistent_ordering(products)

    if filters.product_category_ids.present? || filters.without_product_category.present?
      products = with_product_category(products)
    end
    products = with_product_type(products) if filters.product_type.present?
    products = with_date_range(products, :created_at)

    result.products = paginate(products)
    result
  rescue BaseService::FailedResult
    result
  end

  private

  def base_scope
    Product.where(organization:).ransack(search_params)
  end

  def search_params
    return if search_term.blank?

    {
      m: "or",
      name_cont: search_term,
      code_cont: search_term
    }
  end

  # The product_category dimension is a multi-select: chosen product_categories OR "no product_category".
  def with_product_category(scope)
    scope.in_categories(filters.product_category_ids, include_uncategorized: filters.without_product_category.present?)
  end

  def with_product_type(scope)
    scope.where(product_type: filters.product_type)
  end
end
