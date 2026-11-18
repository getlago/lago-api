# frozen_string_literal: true

module UsageMonitoring
  module Thresholds
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

        if thresholds.size > ThresholdRecord::SOFT_LIMIT
          return failure("too_many_thresholds", meta: {max_items: ThresholdRecord::SOFT_LIMIT})
        end

        return failure("value_is_mandatory") unless all_threshold_values_present?(thresholds)

        if !all_threshold_values_numeric?(thresholds) || !thresholds.all? { value_within_limit?(it[:value]) }
          return failure("value_is_invalid")
        end

        return failure("recurring_value_is_negative") unless all_recurring_threshold_values_positive?(cast_thresholds)
        return failure("duplicate_threshold_values") if duplicate_threshold_values?(cast_thresholds)
        return failure("value_is_invalid") if thresholds.count { recurring_param?(it) } > 1

        validate_notify_on!(thresholds)
        result.success? ? result : result.fail_with_error!(result.error.remap(result) { :thresholds })
      end

      private

      attr_reader :thresholds

      def failure(error_code, meta: {})
        result.single_validation_failure!(field: :thresholds, error_code:, meta:)
      end

      def value_within_limit?(value)
        decimal = BigDecimal(value.to_s).round(5)
        decimal.finite? && decimal.abs < VALUE_LIMIT
      rescue ArgumentError
        false
      end

      def cast_thresholds
        thresholds.map do
          value = BigDecimal(it[:value].to_s).round(5)
          # -0 equals 0 but hashes apart, so the duplicate check would keep both
          it.merge(value: value.zero? ? BigDecimal(0) : value)
        end
      end
    end
  end
end
