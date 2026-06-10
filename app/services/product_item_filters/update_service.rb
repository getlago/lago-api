# frozen_string_literal: true

module ProductItemFilters
  class UpdateService < BaseService
    Result = BaseResult[:product_item_filter]

    def initialize(product_item_filter:, params:)
      @product_item_filter = product_item_filter
      @params = params.to_h.with_indifferent_access
      super
    end

    activity_loggable(
      action: "product_item_filter.updated",
      record: -> { product_item_filter }
    )

    def call
      return result.not_found_failure!(resource: "product_item_filter") unless product_item_filter

      if params.key?(:values)
        values_validation = ProductItemFilters::ValidateValuesService.call(
          product_item: product_item_filter.product_item,
          values_params: params[:values],
          excluded_filter: product_item_filter
        )
        return values_validation unless values_validation.success?
      end

      ActiveRecord::Base.transaction do
        product_item_filter.name = params[:name] if params.key?(:name)
        product_item_filter.description = params[:description] if params.key?(:description)
        product_item_filter.invoice_display_name = params[:invoice_display_name] if params.key?(:invoice_display_name)
        product_item_filter.save!

        replace_values if params.key?(:values)

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

    attr_reader :product_item_filter, :params

    def replace_values
      product_item_filter.values.discard_all!

      params[:values].each do |value_params|
        product_item_filter.values.create!(
          organization_id: product_item_filter.organization_id,
          billable_metric_filter_id: value_params[:billable_metric_filter_id],
          value: value_params[:value]
        )
      end
    end
  end
end
