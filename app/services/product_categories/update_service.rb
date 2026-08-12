# frozen_string_literal: true

module ProductCategories
  class UpdateService < BaseService
    Result = BaseResult[:product_category]

    def initialize(product_category:, params:)
      @product_category = product_category
      @params = params.to_h.with_indifferent_access
      super
    end

    activity_loggable(
      action: "product_category.updated",
      record: -> { product_category }
    )

    def call
      return result.not_found_failure!(resource: "product_category") unless product_category

      product_category.name = params[:name] if params.key?(:name)
      product_category.description = params[:description] if params.key?(:description)
      product_category.invoice_display_name = params[:invoice_display_name] if params.key?(:invoice_display_name)

      # NOTE: code can only be edited while the product_category is not yet in a plan or subscription
      if params.key?(:code) && params[:code]&.strip != product_category.code && product_category.attached_to_plan_or_subscription?
        return result.single_validation_failure!(field: :code, error_code: "attached_to_plan_or_subscription")
      end

      product_category.code = params[:code]&.strip if params.key?(:code)

      product_category.save!

      result.product_category = product_category
      result
    rescue ActiveRecord::RecordInvalid => e
      result.record_validation_failure!(record: e.record)
    end

    private

    attr_reader :product_category, :params
  end
end
