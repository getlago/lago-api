# frozen_string_literal: true

module ProductItemFilters
  class ValidateValuesService < BaseService
    Result = BaseResult

    def initialize(product_item:, values_params:)
      @product_item = product_item
      @values_params = values_params
      super
    end

    def call
      if values_params.blank?
        return result.single_validation_failure!(field: :values, error_code: "value_is_mandatory")
      end

      requested_ids = values_params.map { it[:billable_metric_filter_id].to_s }.uniq
      known_ids = product_item.billable_metric.filters.where(id: requested_ids).ids
      if known_ids.map(&:to_s).sort != requested_ids.sort
        return result.single_validation_failure!(field: :"values.billable_metric_filter", error_code: "value_is_invalid")
      end

      # A key-only entry (no value) matches any value of the key, so combining
      # it with specific values for the same key is contradictory — the
      # wildcard subsumes them.
      key_only_ids = values_params.select { it[:value].nil? }.map { it[:billable_metric_filter_id].to_s }
      specific_ids = values_params.reject { it[:value].nil? }.map { it[:billable_metric_filter_id].to_s }
      if key_only_ids.intersect?(specific_ids)
        return result.single_validation_failure!(field: :values, error_code: "key_only_conflicts_with_values")
      end

      result
    end

    private

    attr_reader :product_item, :values_params
  end
end
