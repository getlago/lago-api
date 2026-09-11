# frozen_string_literal: true

class RateCardsQuery < BaseQuery
  Result = BaseResult[:rate_cards]
  Filters = BaseFilters[
    :product_ids,
    :product_filter_ids,
    :product_category_ids,
    :without_product_category,
    :code,
    :product_code,
    :product_filter_code
  ]

  def call
    rate_cards = base_scope.result
    rate_cards = paginate(rate_cards)
    rate_cards = apply_consistent_ordering(rate_cards)

    rate_cards = with_products(rate_cards) if filters.product_ids.present?
    rate_cards = with_product_filters(rate_cards) if filters.product_filter_ids.present?
    if filters.product_category_ids.present? || filters.without_product_category.present?
      rate_cards = with_product_category(rate_cards)
    end
    rate_cards = with_code(rate_cards) if filters.code.present?
    rate_cards = with_product_code(rate_cards) if filters.product_code.present?
    rate_cards = with_product_filter_code(rate_cards) if filters.product_filter_code.present?

    result.rate_cards = rate_cards
    result
  end

  private

  def base_scope
    RateCard.where(organization:).ransack(search_params)
  end

  def search_params
    return if search_term.blank?

    {
      m: "or",
      name_cont: search_term,
      code_cont: search_term
    }
  end

  def with_products(scope)
    scope.where(product_id: filters.product_ids)
  end

  def with_product_filters(scope)
    scope.where(product_filter_id: filters.product_filter_ids)
  end

  # A rate card reaches a product_category through its product. The dimension is
  # a multi-select: cards on products in the chosen categories OR on products
  # with no category.
  def with_product_category(scope)
    scope.where(product_id: category_scoped_product_ids)
  end

  def category_scoped_product_ids
    products = organization.products

    if filters.product_category_ids.present? && filters.without_product_category.present?
      products.where(product_category_id: filters.product_category_ids)
        .or(products.where(product_category_id: nil)).select(:id)
    elsif filters.without_product_category.present?
      products.where(product_category_id: nil).select(:id)
    else
      products.where(product_category_id: filters.product_category_ids).select(:id)
    end
  end

  def with_code(scope)
    scope.where(code: filters.code)
  end

  def with_product_code(scope)
    scope.where(product_id: organization.products.where(code: filters.product_code).select(:id))
  end

  def with_product_filter_code(scope)
    scope.where(product_filter_id: organization.product_filters.where(code: filters.product_filter_code).select(:id))
  end
end
