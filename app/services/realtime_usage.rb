# frozen_string_literal: true

# Which charges the pre-aggregated usage buckets can answer current usage for. Shared by
# the event store provider, the charge cache gate and the parity task, which must agree.
module RealtimeUsage
  SUPPORTED_AGGREGATION_TYPES = %w[count_agg sum_agg].freeze

  # percentage and custom walk individual events; dynamic needs precise amounts the
  # buckets do not carry.
  SUPPORTED_CHARGE_MODELS = %w[standard graduated package volume graduated_percentage].freeze

  class << self
    # The env var is the deployment-wide kill switch, the flag is the per-organization
    # rollout. The override belongs to the ClickHouse migration comparison, which has to
    # keep comparing two event stores.
    def enabled?(organization)
      return false if Events::Stores::StoreFactory.override
      return false unless Events::Stores::StoreFactory.supports_clickhouse?
      return false unless ActiveModel::Type::Boolean.new.cast(ENV["LAGO_RISINGWAVE_USAGE_ENABLED"])

      organization.feature_flag_enabled?(:realtime_usage)
    end

    def supported_charge?(charge)
      billable_metric = charge.billable_metric

      return false unless SUPPORTED_CHARGE_MODELS.include?(charge.charge_model)
      return false unless SUPPORTED_AGGREGATION_TYPES.include?(billable_metric.aggregation_type)
      return false if charge.pay_in_advance?
      return false if charge.prorated?
      return false if billable_metric.recurring?

      # The pipeline does not evaluate custom expressions yet.
      billable_metric.expression.blank?
    end
  end
end
