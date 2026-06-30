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

      ActiveRecord::Base.transaction do
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
