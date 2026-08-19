# frozen_string_literal: true

module UsageMonitoring
  module Concerns
    module CreateOrUpdateConcern
      extend ActiveSupport::Concern

      def find_billable_metric_from_params!
        if params[:billable_metric]
          params[:billable_metric]
        elsif params[:billable_metric_id]
          organization.billable_metrics.find_by!(id: params[:billable_metric_id])
        elsif params[:billable_metric_code]
          organization.billable_metrics.find_by!(code: params[:billable_metric_code])
        end
      rescue ActiveRecord::RecordNotFound
        result.not_found_failure!(resource: "billable_metric")
      end

      def duplicate_threshold_values?(thresholds)
        threshold_keys = thresholds.map { |t| [t[:value], recurring_param?(t)] }
        threshold_keys.size != threshold_keys.uniq.size
      end

      def recurring_param?(threshold)
        ActiveModel::Type::Boolean.new.cast(threshold[:recurring]) || false
      end

      def all_threshold_values_present?(thresholds)
        thresholds.none? { it[:value].nil? }
      end

      def all_threshold_values_numeric?(thresholds)
        thresholds.all? { |t| valid_numeric_value?(t[:value]) }
      end

      def validate_notify_on!(thresholds)
        if thresholds.any? { notify_on_for(it).any? { |value| AlertThreshold::NOTIFY_ON_VALUES.exclude?(value) } }
          return result.single_validation_failure!(field: "thresholds:notify_on", error_code: "value_is_invalid")
        end

        if thresholds.any? { notify_on_for(it).exclude?(AlertThreshold::NOTIFY_ON_TRIGGERED) }
          return result.single_validation_failure!(field: "thresholds:notify_on", error_code: "triggered_is_mandatory")
        end

        opting_in = thresholds.select { notify_on_for(it).include?(AlertThreshold::NOTIFY_ON_RESOLVED) }

        if opting_in.any? { recurring_param?(it) }
          result.single_validation_failure!(field: "thresholds:notify_on", error_code: "recurring_not_supported")
        elsif opting_in.any? { it[:code].blank? }
          result.single_validation_failure!(field: "thresholds:code", error_code: "value_is_mandatory")
        elsif opted_in_code_not_unique?(thresholds, opting_in)
          result.single_validation_failure!(field: :thresholds, error_code: "duplicate_threshold_codes")
        end
      end

      def all_recurring_threshold_values_positive?(thresholds)
        thresholds.all? do |t|
          value = ActiveModel::Type::Decimal.new.cast(t[:value])

          !recurring_param?(t) || value.positive?
        end
      end

      def notify_on_for(threshold)
        values = threshold[:notify_on]
        return [AlertThreshold::NOTIFY_ON_TRIGGERED] if values.nil?

        Array(values).map(&:to_s)
      end

      def opted_in_code_not_unique?(thresholds, opting_in)
        codes = thresholds.filter_map { it[:code].presence }
        opting_in.any? { codes.count(it[:code]) > 1 }
      end

      def valid_numeric_value?(value)
        case value
        when Numeric
          true
        when String
          return false if value.blank?

          Float(value)
          true
        else
          false
        end
      rescue ArgumentError
        false
      end
    end
  end
end
