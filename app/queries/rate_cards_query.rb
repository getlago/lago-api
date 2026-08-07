# frozen_string_literal: true

class RateCardsQuery < BaseQuery
  Result = BaseResult[:rate_cards]
  Filters = BaseFilters[
    :product_id,
    :product_filter_id,
    :code,
    :product_code,
    :product_filter_code
  ]

  def call
    rate_cards = base_scope.result
    rate_cards = paginate(rate_cards)
    rate_cards = apply_consistent_ordering(rate_cards)

    rate_cards = with_product(rate_cards) if filters.product_id.present?
    rate_cards = with_product_filter(rate_cards) if filters.product_filter_id.present?
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

  def with_product(scope)
    scope.where(product_id: filters.product_id)
  end

  def with_product_filter(scope)
    scope.where(product_filter_id: filters.product_filter_id)
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
