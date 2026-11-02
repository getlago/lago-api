# frozen_string_literal: true

module ProductCategories
  class CreateService < BaseService
    Result = BaseResult[:product_category]

    activity_loggable(
      action: "product_category.created",
      record: -> { result.product_category }
    )

    def initialize(organization:, params:)
      @organization = organization
      @params = params.to_h.with_indifferent_access
      super
    end

    def call
      return result.not_found_failure!(resource: "organization") unless organization

      # A JSON body can send a number or a boolean, which has no strip.
      unless params[:code].nil? || params[:code].is_a?(String)
        return result.single_validation_failure!(field: :code, error_code: "value_is_invalid")
      end

      ActiveRecord::Base.transaction do
        product_category = organization.product_categories.create!(
          name: params[:name],
          code: params[:code]&.strip,
          description: params[:description],
          invoice_display_name: params[:invoice_display_name]
        )

        result.product_category = product_category
        SendWebhookJob.perform_after_commit("product_category.created", product_category)
      end

      result
    rescue ActiveRecord::RecordInvalid => e
      result.record_validation_failure!(record: e.record)
    end

    private

    attr_reader :organization, :params
  end
end
