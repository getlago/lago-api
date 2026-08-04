# frozen_string_literal: true

module Subscriptions
  class TerminateRecurringUsageService < BaseService
    Result = BaseResult[:event]

    def initialize(subscription:, params:, metadata: {})
      @subscription = subscription
      @params = params.to_h.deep_symbolize_keys
      @metadata = metadata

      super
    end

    def call
      if billable_metric_code.blank?
        return result.single_validation_failure!(field: :billable_metric_code, error_code: "value_is_mandatory")
      end
      return result.single_validation_failure!(field: :group, error_code: "value_is_mandatory") if group.blank?
      return result.not_found_failure!(resource: "charge") unless charge
      unless billable_metric.recurring?
        return result.single_validation_failure!(field: :billable_metric_code, error_code: "not_recurring")
      end
      unless supported_aggregation?
        return result.single_validation_failure!(
          field: :billable_metric_code,
          error_code: "unsupported_aggregation_type"
        )
      end
      if missing_group_keys.any?
        return result.validation_failure!(
          errors: {group: missing_group_keys.index_with { ["value_is_mandatory"] }}
        )
      end
      if current_units <= 0
        return result.single_validation_failure!(field: :group, error_code: "no_active_recurring_usage")
      end

      event_result = Events::CreateService.call(
        organization: subscription.organization,
        params: event_params,
        timestamp: event_timestamp.to_f,
        metadata:
      )

      return result.fail_with_error!(event_result.error) unless event_result.success?

      result.event = event_result.event
      result
    rescue ArgumentError
      result.single_validation_failure!(field: :timestamp, error_code: "invalid_format")
    rescue JSON::ParserError
      result.single_validation_failure!(field: :group, error_code: "invalid_format")
    end

    private

    attr_reader :subscription, :params, :metadata

    delegate :billable_metric, to: :charge

    def charge
      return @charge if defined?(@charge)

      scope = subscription.plan.charges
        .joins(:billable_metric)
        .includes(:billable_metric)
        .where(billable_metrics: {code: billable_metric_code})
      scope = scope.where(code: charge_code) if charge_code.present?

      @charge = scope.first
    end

    def supported_aggregation?
      billable_metric.sum_agg?
    end

    def current_units
      @current_units ||= begin
        usage_result = Invoices::CustomerUsageService.call(
          customer: subscription.customer,
          subscription:,
          timestamp: event_timestamp,
          apply_taxes: false,
          with_cache: false,
          usage_filters:
        )
        usage_result.raise_if_error!

        usage_result.usage.fees
          .select { |fee| fee.charge_id == charge.id }
          .sum { |fee| BigDecimal(fee.units.to_s) }
      end
    end

    def usage_filters
      UsageFilters.new(
        filter_by_charge_code: charge.code,
        filter_by_group: group
      )
    end

    def event_params
      {
        transaction_id: transaction_id,
        code: billable_metric.code,
        external_subscription_id: subscription.external_id,
        timestamp: event_timestamp.to_f,
        properties: group.merge(billable_metric.field_name => (-current_units).to_s)
      }
    end

    def transaction_id
      params[:transaction_id].presence || "terminate_recurring_usage-#{SecureRandom.uuid}"
    end

    def event_timestamp
      @event_timestamp ||= if params[:timestamp].present?
        Time.zone.at(BigDecimal(params[:timestamp].to_s))
      else
        Time.current
      end
    end

    def billable_metric_code
      params[:billable_metric_code].to_s.presence
    end

    def charge_code
      params[:charge_code].to_s.presence
    end

    def group
      @group ||= begin
        value = params[:group] || {}
        value = JSON.parse(value) if value.is_a?(String)
        value = value.to_unsafe_h if value.respond_to?(:to_unsafe_h)
        value.to_h.stringify_keys
      end
    end

    def missing_group_keys
      Array(charge.pricing_group_keys) - group.keys
    end
  end
end
