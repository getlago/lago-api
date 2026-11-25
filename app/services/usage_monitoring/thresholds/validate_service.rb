# frozen_string_literal: true

module UsageMonitoring
  module Thresholds
    # Stops at the first failing check. An error on one threshold names its path, such as thresholds[1].value;
    # an error on the list as a whole stays on thresholds.
    class ValidateService < BaseService
      include ::UsageMonitoring::Concerns::CreateOrUpdateConcern

      Result = BaseResult

      VALUE_LIMIT = BigDecimal(10)**25

      def initialize(thresholds:)
        @thresholds = thresholds
        super
      end

      def call
        return failure("value_is_mandatory") if thresholds.blank?
        return failure("value_is_invalid") if !thresholds.is_a?(Array) || !thresholds.all?(Hash)

        if (index = thresholds.index { !single_value?(it[:code]) || !single_value?(it[:recurring]) })
          field = single_value?(thresholds[index][:code]) ? :recurring : :code
          return element_failure(index, field, "value_is_invalid")
        end

        if thresholds.size > ThresholdRecord::SOFT_LIMIT
          return failure("too_many_thresholds", meta: {max_items: ThresholdRecord::SOFT_LIMIT})
        end

        if (index = thresholds.index { it[:value].nil? })
          return element_failure(index, :value, "value_is_mandatory")
        end

        if (index = thresholds.index { !valid_numeric_value?(it[:value]) || !value_within_limit?(it[:value]) })
          return element_failure(index, :value, "value_is_invalid")
        end

        if (index = cast_thresholds.index { recurring_param?(it) && !it[:value].positive? })
          return element_failure(index, :value, "recurring_value_is_negative")
        end

        if (index = later_duplicate_index(cast_thresholds.map { [it[:value], recurring_param?(it)] }))
          return element_failure(index, :value, "duplicate_threshold_values")
        end

        if (index = thresholds.each_index.select { recurring_param?(thresholds[it]) }.second)
          return element_failure(index, :recurring, "value_is_invalid")
        end

        validate_notify_on
      end

      private

      attr_reader :thresholds

      def validate_notify_on
        index, field, error_code = notify_on_violation(thresholds)
        error_code ? element_failure(index, field, error_code) : result
      end

      def failure(error_code, meta: {})
        result.single_validation_failure!(field: :thresholds, error_code:, meta:)
      end

      def element_failure(index, field, error_code)
        result.single_validation_failure!(field: ValidationFailure.item_field(:thresholds, index, field), error_code:)
      end

      def value_within_limit?(value)
        decimal = BigDecimal(value.to_s).round(5)
        decimal.finite? && decimal.abs < VALUE_LIMIT
      rescue ArgumentError
        false
      end

      def cast_thresholds
        @cast_thresholds ||= thresholds.map do
          value = BigDecimal(it[:value].to_s).round(5)
          # -0 equals 0 but hashes apart, so the duplicate check would keep both
          it.merge(value: value.zero? ? BigDecimal(0) : value)
        end
      end
    end
  end
end
