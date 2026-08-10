# frozen_string_literal: true

module ProductCategories
  class CreateService < BaseService
    Result = BaseResult[:product_category]

    def initialize(organization:, params:)
      @organization = organization
      @params = params.to_h.with_indifferent_access
      super
    end

    activity_loggable(
      action: "product_category.created",
      record: -> { result.product_category }
    )

    def call
      return result.not_found_failure!(resource: "organization") unless organization

      product_category = organization.product_categories.create!(
        name: params[:name],
        code: params[:code]&.strip,
        description: params[:description],
        invoice_display_name: params[:invoice_display_name]
      )

      result.product_category = product_category
      result
    rescue ActiveRecord::RecordInvalid => e
      result.record_validation_failure!(record: e.record)
    end

    private

    attr_reader :organization, :params
  end
end
