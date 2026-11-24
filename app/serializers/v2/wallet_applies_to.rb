# frozen_string_literal: true

module V2
  module WalletAppliesTo
    SELECTORS_PRELOAD = {selectors: [:product_category, :product, {product_filter: :product}]}.freeze

    private

    def applies_to = {include: selectors}

    # In the order they were added, sorted in memory so that a list reads its preloaded selectors.
    # Their targets load in one query per kind, also for a wallet that no request preloaded.
    def selectors
      ActiveRecord::Associations::Preloader.new(records: [model], associations: self.class::PRELOADS).call
      model.selectors.sort_by { [it.created_at, it.id] }.map { selector(it) }
    end

    # Each selector as a request names it.
    def selector(selector)
      case selector.selector_type
      when "fee_type"
        {type: "fee_type", code: selector.fee_type}
      when "product_category"
        {type: "product_category", code: selector.product_category.code}
      when "product"
        {type: "product", code: selector.product.code, with_product_filters: selector.with_product_filters}
      when "product_filters"
        {type: "product_filters", product_code: selector.product_filter.product.code, code: selector.product_filter.code}
      end
    end
  end
end
