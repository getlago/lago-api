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
      product.save!

      result.product = product
      result
    rescue ActiveRecord::RecordInvalid => e
      result.record_validation_failure!(record: e.record)
    end

    private

    attr_reader :product, :params
  end
end
