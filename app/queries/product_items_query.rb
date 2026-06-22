# frozen_string_literal: true

class ProductItemsQuery < BaseQuery
  Result = BaseResult[:product_items]
  Filters = BaseFilters[:product_ids, :without_product, :item_type]

  def call
    product_items = base_scope.result
    product_items = paginate(product_items)
    product_items = apply_consistent_ordering(product_items)

    if filters.product_ids.present? || filters.without_product.present?
      product_items = with_product(product_items)
    end
    product_items = with_item_type(product_items) if filters.item_type.present?

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

  # The product dimension is a multi-select: chosen products OR "no product".
  def with_product(scope)
    if filters.product_ids.present? && filters.without_product.present?
      scope.where(product_id: filters.product_ids).or(scope.where(product_id: nil))
    elsif filters.without_product.present?
      scope.where(product_id: nil)
    else
      scope.where(product_id: filters.product_ids)
    end
  end

  def with_item_type(scope)
    scope.where(item_type: filters.item_type)
  end
end
