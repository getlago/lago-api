# frozen_string_literal: true

class ProductsQuery < BaseQuery
  Result = BaseResult[:products]

  def call
    products = base_scope.result
    products = paginate(products)
    products = apply_consistent_ordering(products)

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
end
