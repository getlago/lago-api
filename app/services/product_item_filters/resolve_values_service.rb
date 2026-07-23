# frozen_string_literal: true

module ProductItemFilters
  # The public API references billable metric filters by key — their ids are
  # not exposed on the billable metric payload. Resolve each value entry's
  # `key` to the matching filter of the item's metric; entries already carrying
  # a `billable_metric_filter_id` pass through. An unknown key fails on the
  # `values.key` field — the field the caller actually sent.
  class ResolveValuesService < BaseService
    Result = BaseResult[:values_params]

    def initialize(product_item:, values_params:)
      @product_item = product_item
      @values_params = values_params
      super
    end

    def call
      resolved = Array.wrap(values_params).map do |value_params|
        value_params = value_params.to_h.with_indifferent_access
        next value_params if value_params[:billable_metric_filter_id].present? || value_params[:key].blank?

        metric_filter = product_item.billable_metric&.filters&.find_by(key: value_params[:key])
        unless metric_filter
          return result.single_validation_failure!(field: :"values.key", error_code: "value_is_invalid")
        end

        value_params.except(:key).merge(billable_metric_filter_id: metric_filter.id)
      end

      result.values_params = resolved
      result
    end

    private

    attr_reader :product_item, :values_params
  end
end
