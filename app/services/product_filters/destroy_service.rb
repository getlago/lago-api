# frozen_string_literal: true

module ProductFilters
  class DestroyService < BaseService
    Result = BaseResult[:product_filter]

    def initialize(product_filter:)
      @product_filter = product_filter
      super
    end

    activity_loggable(
      action: "product_filter.deleted",
      record: -> { result.product_filter }
    )

    def call
      return result.not_found_failure!(resource: "product_filter") unless product_filter

      # Same rule as product_categories and items: a catalog object cannot be deleted while
      # its item is attached to a plan or subscription. Detach first, then delete.
      if product_filter.attached_to_plan_or_subscription?
        return result.single_validation_failure!(field: :product_filter, error_code: "attached_to_plan_or_subscription")
      end

      ActiveRecord::Base.transaction do
        # Rate cards scoped to this filter lose their scope when it is deleted, so
        # discard them too (all unattached, guaranteed by the guard above) — mirrors
        # the product destroy cascade and avoids orphaned rate cards.
        scoped_cards = product_filter.product.rate_cards.where(product_filter_id: product_filter.id)
        RateCardRate.where(rate_card_id: scoped_cards.ids).discard_all!
        scoped_cards.discard_all!

        product_filter.values.discard_all!
        product_filter.discard!
      end

      result.product_filter = product_filter
      result
    end

    private

    attr_reader :product_filter
  end
end
