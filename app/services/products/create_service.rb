# frozen_string_literal: true

module Products
  class CreateService < BaseService
    Result = BaseResult[:product]

    def initialize(organization:, params:)
      @organization = organization
      @params = params.to_h.with_indifferent_access
      super
    end

    activity_loggable(
      action: "product.created",
      record: -> { result.product }
    )

    def call
      return result.not_found_failure!(resource: "organization") unless organization

      product_category = nil
      if params[:product_category_id].present?
        product_category = organization.product_categories.find_by(id: params[:product_category_id])
        return result.not_found_failure!(resource: "product_category") unless product_category
      end

      billable_metric = nil
      if params[:billable_metric_id].present?
        billable_metric = organization.billable_metrics.find_by(id: params[:billable_metric_id])
        return result.not_found_failure!(resource: "billable_metric") unless billable_metric
      end

      product = Product.create!(
        organization:,
        product_category:,
        billable_metric:,
        product_type: params[:product_type],
        name: params[:name],
        code: params[:code]&.strip,
        description: params[:description],
        invoice_display_name: params[:invoice_display_name]
      )

      result.product = product
      result
    rescue ActiveRecord::RecordInvalid => e
      result.record_validation_failure!(record: e.record)
    end

    private

    attr_reader :organization, :params
  end
end
