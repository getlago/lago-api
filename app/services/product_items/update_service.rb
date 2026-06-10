# frozen_string_literal: true

module ProductItems
  class UpdateService < BaseService
    Result = BaseResult[:product_item]

    def initialize(product_item:, params:)
      @product_item = product_item
      @params = params.to_h.with_indifferent_access
      super
    end

    activity_loggable(
      action: "product_item.updated",
      record: -> { product_item }
    )

    def call
      return result.not_found_failure!(resource: "product_item") unless product_item

      product_item.name = params[:name] if params.key?(:name)
      product_item.description = params[:description] if params.key?(:description)
      product_item.invoice_display_name = params[:invoice_display_name] if params.key?(:invoice_display_name)
      product_item.save!

      result.product_item = product_item
      result
    rescue ActiveRecord::RecordInvalid => e
      result.record_validation_failure!(record: e.record)
    end

    private

    attr_reader :product_item, :params
  end
end
