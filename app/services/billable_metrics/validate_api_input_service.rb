# frozen_string_literal: true

module BillableMetrics
  class ValidateApiInputService < BaseService
    Result = BaseResult

    ENUMS = {
      aggregation_type: BillableMetric::AGGREGATION_TYPES.keys.map(&:to_s),
      rounding_function: BillableMetric::ROUNDING_FUNCTIONS.values,
      weighted_interval: BillableMetric::WEIGHTED_INTERVAL.values
    }.freeze
    STRING_FIELDS = %i[name code description field_name expression].freeze

    def initialize(params:)
      @params = params
      super
    end

    def call
      errors = {}

      ENUMS.each do |field, values|
        next unless params.key?(field)
        next if params[field].nil? && field != :aggregation_type

        errors[field] = ["value_is_invalid"] unless values.include?(params[field])
      end

      STRING_FIELDS.each do |field|
        if !params[field].nil? && !params[field].is_a?(String)
          errors[field] = ["value_is_invalid"]
        end
      end

      if params.key?(:recurring) && ![true, false, "true", "false", 0, 1, "0", "1"].include?(params[:recurring])
        errors[:recurring] = ["value_is_invalid"]
      end

      unless valid_rounding_precision?(params[:rounding_precision])
        errors[:rounding_precision] = ["value_is_invalid"]
      end

      errors.merge!(filter_errors)

      if errors.any?
        result.validation_failure!(errors:)
      end
      result
    end

    private

    attr_reader :params

    def valid_rounding_precision?(value)
      case value
      when nil, Integer then true
      when String then value.match?(/\A[+-]?\d+\z/)
      else false
      end
    end

    def filter_errors
      errors = {}
      seen_keys = {}

      (params[:filters] || []).each_with_index do |filter, index|
        key = filter[:key]
        key_error = if !key.nil? && !key.is_a?(String)
          "value_is_invalid"
        elsif key.blank?
          "value_is_mandatory"
        elsif seen_keys.key?(key)
          "value_already_exist"
        end

        errors[:"filters[#{index}].key"] = [key_error] if key_error
        errors[:"filters[#{index}].values"] = ["value_is_mandatory"] if filter[:values].blank?
        seen_keys[key] = true
      end

      errors
    end
  end
end
