# frozen_string_literal: true

module ProductFilters
  # The public API references billable metric filters by key — their ids are
  # not exposed on the billable metric payload. Resolve each value entry's
  # `key` to the matching filter of the item's metric, and keep the key so that a
  # later error names the field the caller sent; entries already carrying a
  # `billable_metric_filter_id` (GraphQL) pass through.
  class ResolveValuesService < BaseService
    Result = BaseResult[:values_params]

    # The field of the value at index: REST names the metric filter of a value by its key.
    def self.field(value_params, index, field)
      field = :key if field.to_sym == :billable_metric_filter && value_params.key?(:key)
      BaseService::ValidationFailure.item_field(:values, index, field)
    end

    def initialize(product:, values_params:)
      @product = product
      @values_params = values_params
      super
    end

    def call
      resolved = Array.wrap(values_params).map.with_index do |value_params, index|
        value_params = value_params.to_h.with_indifferent_access
        # GraphQL always sends the id, even blank, and REST never does.
        next value_params if value_params.key?(:billable_metric_filter_id)

        if value_params[:key].blank?
          return result.single_validation_failure!(field: self.class.field(value_params, index, :key), error_code: "value_is_mandatory")
        end

        metric_filter = product.billable_metric&.filters&.find_by(key: value_params[:key])
        unless metric_filter
          return result.single_validation_failure!(field: self.class.field(value_params, index, :key), error_code: "value_is_invalid")
        end

        value_params.merge(billable_metric_filter_id: metric_filter.id)
      end

      result.values_params = resolved
      result
    end

    private

    attr_reader :product, :values_params
  end
end
