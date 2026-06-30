# frozen_string_literal: true

module ProductItemFilters
  class ValidateValuesService < BaseService
    Result = BaseResult

    def initialize(product_item:, values_params:, excluded_filter: nil)
      @product_item = product_item
      @values_params = values_params
      @excluded_filter = excluded_filter
      super
    end

    def call
      if values_params.blank?
        return result.single_validation_failure!(field: :values, error_code: "value_is_mandatory")
      end

      requested_ids = values_params.map { it[:billable_metric_filter_id].to_s }.uniq
      known_ids = product_item.billable_metric.filters.where(id: requested_ids).ids
      if known_ids.map(&:to_s).sort != requested_ids.sort
        return result.single_validation_failure!(field: :"values.billable_metric_filter_id", error_code: "value_is_invalid")
      end

      if combination_already_used?
        return result.single_validation_failure!(field: :values, error_code: "combination_already_exists")
      end

      result
    end

    private

    attr_reader :product_item, :values_params, :excluded_filter

    def combination_already_used?
      combination = values_params.map { [it[:billable_metric_filter_id].to_s, it[:value].to_s] }.to_set

      scope = product_item.filters.includes(:values)
      scope = scope.where.not(id: excluded_filter.id) if excluded_filter

      scope.any? do |filter|
        filter.values.map { [it.billable_metric_filter_id, it.value] }.to_set == combination
      end
    end
  end
end
