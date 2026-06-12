# frozen_string_literal: true

class RateCardsQuery < BaseQuery
  Result = BaseResult[:rate_cards]
  Filters = BaseFilters[:product_item_id, :product_item_filter_id]

  def call
    rate_cards = base_scope.result
    rate_cards = paginate(rate_cards)
    rate_cards = apply_consistent_ordering(rate_cards)

    rate_cards = with_product_item(rate_cards) if filters.product_item_id.present?
    rate_cards = with_product_item_filter(rate_cards) if filters.product_item_filter_id.present?

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

  def with_product_item(scope)
    scope.where(product_item_id: filters.product_item_id)
  end

  def with_product_item_filter(scope)
    scope.where(product_item_filter_id: filters.product_item_filter_id)
  end
end
