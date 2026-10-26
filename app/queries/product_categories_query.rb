# frozen_string_literal: true

class ProductCategoriesQuery < BaseQuery
  Result = BaseResult[:product_categories]
  Filters = BaseFilters[:created_at_from, :created_at_to]

  def call
    product_categories = base_scope.result
    product_categories = apply_consistent_ordering(product_categories)
    product_categories = with_date_range(product_categories, :created_at)

    result.product_categories = paginate(product_categories)
    result
  rescue BaseService::FailedResult
    result
  end

  private

  def base_scope
    ProductCategory.where(organization:).ransack(search_params)
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
