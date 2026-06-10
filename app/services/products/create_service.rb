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

      product = organization.products.create!(
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
