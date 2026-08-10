# frozen_string_literal: true

module ProductFilters
  class CreateService < BaseService
    Result = BaseResult[:product_filter]

    def initialize(product:, params:)
      @product = product
      @params = params.to_h.with_indifferent_access
      super
    end

    activity_loggable(
      action: "product_filter.created",
      record: -> { result.product_filter }
    )

    def call
      return result.not_found_failure!(resource: "product") unless product

      unless product.usage?
        return result.single_validation_failure!(field: :product, error_code: "not_allowed_for_product_type")
      end

      return resolved_values unless resolved_values.success?

      product.with_lock do
        values_validation = ProductFilters::ValidateValuesService.call(product:, values_params: resolved_values.values_params)
        return values_validation unless values_validation.success?

        product_filter = product.filters.create!(
          organization_id: product.organization_id,
          name: params[:name],
          code: params[:code]&.strip,
          description: params[:description],
          invoice_display_name: params[:invoice_display_name]
        )

        create_values(product_filter)

        result.product_filter = product_filter
      end

      result
    rescue ActiveRecord::RecordInvalid => e
      if e.record.is_a?(ProductFilterValue)
        errors = e.record.errors.messages.transform_keys { |key| :"values.#{key}" }
        result.validation_failure!(errors:)
      else
        result.record_validation_failure!(record: e.record)
      end
    end

    private

    attr_reader :product, :params

    def resolved_values
      @resolved_values ||= ProductFilters::ResolveValuesService.call(product:, values_params: params[:values])
    end

    def create_values(product_filter)
      resolved_values.values_params.each do |value_params|
        product_filter.values.create!(
          organization_id: product.organization_id,
          billable_metric_filter_id: value_params[:billable_metric_filter_id],
          value: value_params[:value]
        )
      end
    end
  end
end
