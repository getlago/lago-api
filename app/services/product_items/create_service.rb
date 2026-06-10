# frozen_string_literal: true

module ProductItems
  class CreateService < BaseService
    Result = BaseResult[:product_item]

    def initialize(organization:, params:)
      @organization = organization
      @params = params.to_h.with_indifferent_access
      super
    end

    activity_loggable(
      action: "product_item.created",
      record: -> { result.product_item }
    )

    def call
      return result.not_found_failure!(resource: "organization") unless organization

      product = nil
      if params[:product_id].present?
        product = organization.products.find_by(id: params[:product_id])
        return result.not_found_failure!(resource: "product") unless product
      end

      billable_metric = nil
      if params[:billable_metric_id].present?
        billable_metric = organization.billable_metrics.find_by(id: params[:billable_metric_id])
        return result.not_found_failure!(resource: "billable_metric") unless billable_metric
      end

      product_item = ProductItem.create!(
        organization:,
        product:,
        billable_metric:,
        item_type: params[:item_type],
        name: params[:name],
        code: params[:code]&.strip,
        description: params[:description],
        invoice_display_name: params[:invoice_display_name]
      )

      result.product_item = product_item
      result
    rescue ActiveRecord::RecordInvalid => e
      result.record_validation_failure!(record: e.record)
    end

    private

    attr_reader :organization, :params
  end
end
