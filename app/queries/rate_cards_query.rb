# frozen_string_literal: true

class RateCardsQuery < BaseQuery
  Result = BaseResult[:rate_cards]
  Filters = BaseFilters[
    :product_ids,
    :product_filter_ids,
    :product_category_ids,
    :without_product_category,
    :code,
    :currency,
    :product_code,
    :product_filter_code,
    :exclude_priced_on_plan_id,
    :exclude_priced_on_contract_id
  ]

  def call
    validate_filters
    return result if result.error.present?

    rate_cards = base_scope.result
    rate_cards = apply_consistent_ordering(rate_cards)

    rate_cards = with_products(rate_cards) if filters.product_ids.present?
    rate_cards = with_product_filters(rate_cards) if filters.product_filter_ids.present?
    if filters.product_category_ids.present? || filters.without_product_category.present?
      rate_cards = with_product_category(rate_cards)
    end
    rate_cards = with_code(rate_cards) if filters.code.present?
    rate_cards = with_currency(rate_cards) if filters.currency.present?
    rate_cards = with_product_code(rate_cards) if filters.product_code.present?
    rate_cards = with_product_filter_code(rate_cards) if filters.product_filter_code.present?
    rate_cards = without_priced_on(rate_cards, catalog_plan.applied_rate_cards) if filters.exclude_priced_on_plan_id.present?
    rate_cards = without_priced_on(rate_cards, contract.applied_rate_cards) if filters.exclude_priced_on_contract_id.present?

    result.rate_cards = paginate(rate_cards)
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

  # A rate card reaches a product_category through its product, so scope the
  # cards to the matching products (shared Product.in_categories rule).
  def with_product_category(scope)
    matching_products = organization.products.in_categories(
      filters.product_category_ids,
      include_uncategorized: filters.without_product_category.present?
    )
    scope.where(product_id: matching_products.select(:id))
  end

  def with_code(scope)
    scope.where(code: filters.code)
  end

  def with_currency(scope)
    scope.where(currency: filters.currency)
  end

  def with_product_code(scope)
    scope.where(product_id: organization.products.where(code: filters.product_code).select(:id))
  end

  def with_product_filter_code(scope)
    scope.where(product_filter_id: organization.product_filters.where(code: filters.product_filter_code).select(:id))
  end

  # The create services accept one applied card per (product, product filter) slice: a card of a
  # priced slice cannot be applied there.
  def without_priced_on(scope, applied_rate_cards)
    priced = applied_rate_cards
      .joins("INNER JOIN rate_cards priced_rate_cards ON priced_rate_cards.id = #{applied_rate_cards.table_name}.rate_card_id")
      .where("priced_rate_cards.product_id = rate_cards.product_id")
      .where("priced_rate_cards.product_filter_id IS NOT DISTINCT FROM rate_cards.product_filter_id")

    scope.where.not(priced.arel.exists)
  end

  def validate_filters
    if filters.exclude_priced_on_plan_id.present? && catalog_plan.nil?
      result.not_found_failure!(resource: "plan")
    elsif filters.exclude_priced_on_contract_id.present? && contract.nil?
      result.not_found_failure!(resource: "contract")
    end
  end

  def catalog_plan
    @catalog_plan ||= organization.catalog_plans.find_by(id: filters.exclude_priced_on_plan_id)
  end

  def contract
    @contract ||= organization.contracts.find_by(id: filters.exclude_priced_on_contract_id)
  end
end
