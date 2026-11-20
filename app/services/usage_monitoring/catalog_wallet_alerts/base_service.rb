# frozen_string_literal: true

module UsageMonitoring
  module CatalogWalletAlerts
    class BaseService < UsageMonitoring::BaseService
      private

      # The checks of every alert family, then the wallet rules: values are cents, so a fraction is refused
      # rather than truncated. A balance never goes below 0, so a balance alert has no line below it either,
      # a recurring one included
      def validate_thresholds(thresholds, alert_type)
        validation = Thresholds::ValidateService.call(thresholds:)
        return result.fail_with_error!(validation.error) unless validation.success?

        wallet_values = thresholds.all? { BigDecimal(it[:value].to_s).frac.zero? } &&
          (alert_type != "balance" || lowest_line(thresholds) >= 0)
        result.single_validation_failure!(field: :thresholds, error_code: "value_is_invalid") unless wallet_values
      end

      # A recurring step adds lines below the lowest one-time threshold, from 0 when there is none
      def lowest_line(thresholds)
        recurring, one_time = thresholds.partition { ActiveModel::Type::Boolean.new.cast(it[:recurring]) }
        lowest = one_time.map { BigDecimal(it[:value].to_s) }.min

        if recurring.empty?
          lowest
        else
          (lowest || 0) - BigDecimal(recurring.first[:value].to_s)
        end
      end

      def validate_single_values(params, fields)
        invalid = fields.reject { single_value?(params[it]) }
        result.validation_failure!(errors: invalid.index_with { ["value_is_invalid"] }) if invalid.any?
      end
    end
  end
end
