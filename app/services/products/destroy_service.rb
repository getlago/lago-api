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

      ActiveRecord::Base.transaction do
        product.product_items.find_each do |product_item|
          ProductItems::DestroyService.call!(product_item:)
        end

        product.discard!
      end

      result.product = product
      result
    rescue BaseService::FailedResult => e
      e.result
    end

    private

    attr_reader :product
  end
end
