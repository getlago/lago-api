# frozen_string_literal: true

class ProductsQuery < BaseQuery
  Result = BaseResult[:products]
  Filters = BaseFilters[:product_category_ids, :without_product_category, :product_type]

  def call
    products = base_scope.result.includes(:product_category, :billable_metric)
    products = paginate(products)
    products = apply_consistent_ordering(products)

    if filters.product_category_ids.present? || filters.without_product_category.present?
      products = with_product_category(products)
    end
    products = with_product_type(products) if filters.product_type.present?

    result.products = products
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
    if filters.product_category_ids.present? && filters.without_product_category.present?
      scope.where(product_category_id: filters.product_category_ids).or(scope.where(product_category_id: nil))
    elsif filters.without_product_category.present?
      scope.where(product_category_id: nil)
    else
      scope.where(product_category_id: filters.product_category_ids)
    end
  end

  def with_product_type(scope)
    scope.where(product_type: filters.product_type)
  end
end
