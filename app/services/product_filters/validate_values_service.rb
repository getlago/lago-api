# frozen_string_literal: true

module ProductFilters
  class ValidateValuesService < BaseService
    Result = BaseResult

    # NOTE: product_filter is the filter being updated.
    def initialize(product:, values_params:, product_filter: nil)
      @product = product
      @values_params = values_params
      @product_filter = product_filter
      super
    end

    def call
      if values_params.blank?
        return result.single_validation_failure!(field: :values, error_code: "value_is_mandatory")
      end

      requested_ids = values_params.map { it[:billable_metric_filter_id].to_s }.uniq
      known_ids = product.billable_metric.filters.where(id: requested_ids).ids
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

      if duplicate_value_set?
        return result.single_validation_failure!(field: :values, error_code: "value_already_exist")
      end

      result
    end

    private

    attr_reader :product, :values_params, :product_filter

    def duplicate_value_set?
      submitted = normalized(values_params)

      product.filters.where.not(id: product_filter&.id).includes(:values).any? do |filter|
        normalized(filter.values.map { {billable_metric_filter_id: it.billable_metric_filter_id, value: it.value} }) == submitted
      end
    end

    def normalized(entries)
      entries.map { [it[:billable_metric_filter_id].to_s, it[:value].to_s] }.sort
    end
  end
end
