# frozen_string_literal: true

class ProductItemsQuery < BaseQuery
  Result = BaseResult[:product_items]
  Filters = BaseFilters[:product_id, :item_types]

  def call
    product_items = base_scope.result
    product_items = paginate(product_items)
    product_items = apply_consistent_ordering(product_items)

    product_items = with_product(product_items) if filters.product_id.present?
    product_items = with_item_types(product_items) if filters.item_types.present?

    result.product_items = product_items
    result
  end

  private

  def base_scope
    ProductItem.where(organization:).ransack(search_params)
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

  def with_item_types(scope)
    scope.where(item_type: filters.item_types)
  end
end
