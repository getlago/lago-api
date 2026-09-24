# frozen_string_literal: true

# Shared by the event store provider, the charge cache gate and the parity task, which must
# agree on what the buckets can answer.
module RealtimeUsage
  SUPPORTED_AGGREGATION_TYPES = %w[count_agg sum_agg].freeze

  # percentage and custom walk individual events; dynamic needs precise amounts the buckets
  # do not carry.
  SUPPORTED_CHARGE_MODELS = %w[standard graduated package volume graduated_percentage].freeze

  FORCED_GATE_KEY = :lago_realtime_usage_forced_gate

  class << self
    # Opens the flag and the kill switch for the duration of the block. Reserved for the parity
    # comparison, which has to exercise the bucket path on an organization the flag is off for;
    # production callers never open it.
    def with_forced_gate
      raise "RealtimeUsage gate already forced" if forced_gate?

      Thread.current[FORCED_GATE_KEY] = true
      begin
        yield
      ensure
        Thread.current[FORCED_GATE_KEY] = nil
      end
    end

    def forced_gate?
      Thread.current[FORCED_GATE_KEY].present?
    end

    # The override belongs to the ClickHouse migration comparison, which has to keep
    # comparing two event stores.
    def enabled?(organization)
      return false unless License.premium?
      return false if Events::Stores::StoreFactory.override
      return false unless Events::Stores::StoreFactory.supports_clickhouse?
      return false unless organization.clickhouse_events_store?
      return true if forced_gate?
      return false unless ActiveModel::Type::Boolean.new.cast(ENV["LAGO_REALTIME_USAGE_ENABLED"])

      organization.feature_flag_enabled?(:realtime_usage)
    end

    def supported_charge?(charge)
      unsupported_reason(charge).nil?
    end

    def unsupported_reason(charge)
      billable_metric = charge.billable_metric

      return "unsupported_charge_model" unless SUPPORTED_CHARGE_MODELS.include?(charge.charge_model)
      return "unsupported_aggregation_type" unless SUPPORTED_AGGREGATION_TYPES.include?(billable_metric.aggregation_type)
      return "pay_in_advance" if charge.pay_in_advance?
      return "prorated" if charge.prorated?
      return "recurring_metric" if billable_metric.recurring?

      # `target_wallet_code` will be handled later.
      return "target_wallet" if charge.accepts_target_wallet

      # The pipeline does not evaluate custom expressions yet.
      return "expression" if billable_metric.expression.present?

      nil
    end
  end
end
