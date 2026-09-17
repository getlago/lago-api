# frozen_string_literal: true

class ProductCategoriesQuery < BaseQuery
  Result = BaseResult[:product_categories]

  def call
    product_categories = base_scope.result
    product_categories = paginate(product_categories)
    product_categories = apply_consistent_ordering(product_categories)

    result.product_categories = product_categories
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
