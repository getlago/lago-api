# frozen_string_literal: true

module ProductCategories
  class DestroyService < BaseService
    Result = BaseResult[:product_category]

    def initialize(product_category:)
      @product_category = product_category
      super
    end

    activity_loggable(
      action: "product_category.deleted",
      record: -> { result.product_category }
    )

    def call
      return result.not_found_failure!(resource: "product_category") unless product_category

      ActiveRecord::Base.transaction do
        product_category.products.find_each do |product|
          Products::DestroyService.call!(product:)
        end

        product_category.discard!
      end

      result.product_category = product_category
      result
    rescue BaseService::FailedResult => e
      e.result
    end

    private

    attr_reader :product_category
  end
end
