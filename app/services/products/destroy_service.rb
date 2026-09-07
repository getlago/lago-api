# frozen_string_literal: true

module Products
  class DestroyService < BaseService
    Result = BaseResult[:product]

    def initialize(product:)
      @product = product
      super
    end

    activity_loggable(
      action: "product.deleted",
      record: -> { result.product }
    )

    def call
      return result.not_found_failure!(resource: "product") unless product

      if product.attached_to_plan_or_subscription?
        return result.single_validation_failure!(field: :product, error_code: "attached_to_plan_or_subscription")
      end

      ActiveRecord::Base.transaction do
        ProductFilterValue.where(product_filter_id: product.filters.ids).discard_all!
        product.filters.discard_all!
        RateCardRate.where(rate_card_id: product.rate_cards.ids).discard_all!
        product.rate_cards.discard_all!
        product.discard!
      end

      result.product = product
      result
    end

    private

    attr_reader :product
  end
end
