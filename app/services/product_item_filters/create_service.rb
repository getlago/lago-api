# frozen_string_literal: true

module ProductItemFilters
  class CreateService < BaseService
    Result = BaseResult[:product_item_filter]

    def initialize(product_item:, params:)
      @product_item = product_item
      @params = params.to_h.with_indifferent_access
      super
    end

    activity_loggable(
      action: "product_item_filter.created",
      record: -> { result.product_item_filter }
    )

    def call
      return result.not_found_failure!(resource: "product_item") unless product_item

      unless product_item.usage?
        return result.single_validation_failure!(field: :product_item, error_code: "invalid_item_type")
      end

      values_validation = ProductItemFilters::ValidateValuesService.call(product_item:, values_params: params[:values])
      return values_validation unless values_validation.success?

      ActiveRecord::Base.transaction do
        product_item_filter = product_item.filters.create!(
          organization_id: product_item.organization_id,
          name: params[:name],
          code: params[:code]&.strip,
          description: params[:description],
          invoice_display_name: params[:invoice_display_name]
        )

        create_values(product_item_filter)

        result.product_item_filter = product_item_filter
      end

      result
    rescue ActiveRecord::RecordInvalid => e
      if e.record.is_a?(ProductItemFilterValue)
        errors = e.record.errors.messages.transform_keys { |key| :"values.#{key}" }
        result.validation_failure!(errors:)
      else
        result.record_validation_failure!(record: e.record)
      end
    end

    private

    attr_reader :product_item, :params

    def create_values(product_item_filter)
      params[:values].each do |value_params|
        product_item_filter.values.create!(
          organization_id: product_item.organization_id,
          billable_metric_filter_id: value_params[:billable_metric_filter_id],
          value: value_params[:value]
        )
      end
    end
  end
end
