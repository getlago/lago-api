# frozen_string_literal: true

module ProductItemFilters
  class DestroyService < BaseService
    Result = BaseResult[:product_item_filter]

    def initialize(product_item_filter:)
      @product_item_filter = product_item_filter
      super
    end

    activity_loggable(
      action: "product_item_filter.deleted",
      record: -> { result.product_item_filter }
    )

    def call
      return result.not_found_failure!(resource: "product_item_filter") unless product_item_filter

      # Same rule as products and items: a catalog object cannot be deleted while
      # its item is attached to a plan or subscription. Detach first, then delete.
      if product_item_filter.attached_to_plan_or_subscription?
        return result.single_validation_failure!(field: :product_item_filter, error_code: "attached_to_plan_or_subscription")
      end

      ActiveRecord::Base.transaction do
        # Rate cards scoped to this filter lose their scope when it is deleted, so
        # discard them too (all unattached, guaranteed by the guard above) — mirrors
        # the product item destroy cascade and avoids orphaned rate cards.
        scoped_cards = product_item_filter.product_item.rate_cards.where(product_item_filter_id: product_item_filter.id)
        RateCardRate.where(rate_card_id: scoped_cards.ids).discard_all!
        scoped_cards.discard_all!

        product_item_filter.values.discard_all!
        product_item_filter.discard!
      end

      result.product_item_filter = product_item_filter
      result
    end

    private

    attr_reader :product_item_filter
  end
end
