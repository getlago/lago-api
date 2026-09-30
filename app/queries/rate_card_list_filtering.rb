# frozen_string_literal: true

# The filters of the plan and contract rate card pages. A card only holds its
# rate card, so the catalog filters (product, product filter, category,
# product type, search) narrow the rate cards first; rate overrides live on
# the card's own phases.
module RateCardListFiltering
  FILTERS = %i[
    product_ids product_filter_ids without_product_filter product_category_ids
    without_product_category product_type has_rate_overrides
  ].freeze
  RATE_CARD_FILTERS = (FILTERS - [:has_rate_overrides]).freeze

  private

  def apply_rate_card_filters(scope, phase_parent:)
    rate_cards = matching_rate_cards
    scope = scope.where(rate_card_id: rate_cards.select(:id)) if rate_cards

    if filters.has_rate_overrides.nil?
      scope
    else
      with_rate_overrides(scope, phase_parent:)
    end
  end

  def matching_rate_cards
    return if search_term.blank? && RATE_CARD_FILTERS.all? { filters.public_send(it).blank? }

    rate_cards = RateCard.where(organization:)
    rate_cards = rate_cards.ransack(m: "or", name_cont: search_term, code_cont: search_term).result if search_term.present?
    rate_cards = rate_cards.where(product_id: filters.product_ids) if filters.product_ids.present?
    rate_cards = rate_cards.where(product_id: organization.products.where(product_type: filters.product_type).select(:id)) if filters.product_type.present?
    rate_cards = with_product_filters(rate_cards) if filters.product_filter_ids.present? || filters.without_product_filter.present?

    if filters.product_category_ids.present? || filters.without_product_category.present?
      products = organization.products.in_categories(filters.product_category_ids, include_uncategorized: filters.without_product_category.present?)
      rate_cards = rate_cards.where(product_id: products.select(:id))
    end

    rate_cards
  end

  # "Not defined" is a card priced on the product itself, without a filter.
  def with_product_filters(rate_cards)
    unfiltered = filters.without_product_filter.present? ? [nil] : []
    rate_cards.where(product_filter_id: Array(filters.product_filter_ids) + unfiltered)
  end

  # Phases hang off either a plan card or a contract card: the other parent is
  # NULL, and a NULL in a NOT IN list would match nothing.
  def with_rate_overrides(scope, phase_parent:)
    overriding_ids = RatePhase.where(organization:).where.not(rate_override_id: nil).where.not(phase_parent => nil).select(phase_parent)

    if ActiveModel::Type::Boolean.new.cast(filters.has_rate_overrides)
      scope.where(id: overriding_ids)
    else
      scope.where.not(id: overriding_ids)
    end
  end
end
