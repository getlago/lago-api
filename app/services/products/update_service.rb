# frozen_string_literal: true

module Products
  class UpdateService < BaseService
    Result = BaseResult[:product]

    def initialize(product:, params:)
      @product = product
      @params = params.to_h.with_indifferent_access
      super
    end

    activity_loggable(
      action: "product.updated",
      record: -> { product }
    )

    def call
      return result.not_found_failure!(resource: "product") unless product

      product.name = params[:name] if params.key?(:name)
      product.description = params[:description] if params.key?(:description)
      product.invoice_display_name = params[:invoice_display_name] if params.key?(:invoice_display_name)

      if product.attached_to_plan_or_subscription?
        if params.key?(:code) && params[:code]&.strip != product.code
          return result.single_validation_failure!(field: :code, error_code: "attached_to_plan_or_subscription")
        end

        if params.key?(:product_category_id) && params[:product_category_id] != product.product_category_id
          return result.single_validation_failure!(field: :product_category, error_code: "attached_to_plan_or_subscription")
        end
      else
        product.code = params[:code]&.strip if params.key?(:code)
        assign_product_category if params.key?(:product_category_id)
      end

      return result if result.failure?

      product.save!

      result.product = product
      result
    rescue ActiveRecord::RecordInvalid => e
      result.record_validation_failure!(record: e.record)
    end

    private

    attr_reader :product, :params

    def assign_product_category
      if params[:product_category_id].blank?
        product.product_category = nil
        return
      end

      product_category = product.organization.product_categories.find_by(id: params[:product_category_id])
      return result.not_found_failure!(resource: "product_category") unless product_category

      product.product_category = product_category
    end
  end
end
