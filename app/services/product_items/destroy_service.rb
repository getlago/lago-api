# frozen_string_literal: true

module ProductItems
  class DestroyService < BaseService
    Result = BaseResult[:product_item]

    def initialize(product_item:)
      @product_item = product_item
      super
    end

    activity_loggable(
      action: "product_item.deleted",
      record: -> { result.product_item }
    )

    def call
      return result.not_found_failure!(resource: "product_item") unless product_item

      ActiveRecord::Base.transaction do
        ProductItemFilterValue.where(product_item_filter_id: product_item.filters.ids).discard_all!
        product_item.filters.discard_all!
        RateCardRate.where(rate_card_id: product_item.rate_cards.ids).discard_all!
        product_item.rate_cards.discard_all!
        product_item.discard!
      end

      result.product_item = product_item
      result
    end

    private

    attr_reader :product_item
  end
end
