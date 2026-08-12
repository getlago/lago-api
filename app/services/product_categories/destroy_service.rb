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

      if product_category.attached_to_plan_or_subscription?
        return result.single_validation_failure!(field: :product_category, error_code: "attached_to_plan_or_subscription")
      end

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
