# frozen_string_literal: true

# Which charges the pre-aggregated usage buckets can answer current usage for. Shared by
# the event store provider, the charge cache gate and the parity task, which must agree.
module RealtimeUsage
  SUPPORTED_AGGREGATION_TYPES = %w[count_agg sum_agg].freeze

  # percentage and custom walk individual events; dynamic needs precise amounts the
  # buckets do not carry.
  SUPPORTED_CHARGE_MODELS = %w[standard graduated package volume graduated_percentage].freeze

  class << self
    # Premium only. The env var is the deployment-wide kill switch, the flag is the
    # per-organization rollout. The override belongs to the ClickHouse migration comparison,
    # which has to keep comparing two event stores.
    #
    # The buckets and the ClickHouse events store are fed by the same stream, so they agree
    # by construction. An organization still reading Postgres has no such guarantee: its
    # current usage would come from the stream while its invoices keep counting the rows of
    # the `events` table, and the unique index on that table drops duplicates the stream
    # counts. The two would disagree with nothing to reconcile them.
    def enabled?(organization)
      return false unless License.premium?
      return false if Events::Stores::StoreFactory.override
      return false unless Events::Stores::StoreFactory.supports_clickhouse?
      return false unless ActiveModel::Type::Boolean.new.cast(ENV["LAGO_REALTIME_USAGE_ENABLED"])
      return false unless organization.clickhouse_events_store?

      organization.feature_flag_enabled?(:realtime_usage)
    end

    # The stream counts every event it receives, so an organization whose store drops
    # duplicates gets a different number from the buckets by construction.
    def deduplicated?(organization)
      organization.clickhouse_events_store? && organization.clickhouse_deduplication_enabled?
    end

    def supported_charge?(charge)
      billable_metric = charge.billable_metric

      return false unless SUPPORTED_CHARGE_MODELS.include?(charge.charge_model)
      return false unless SUPPORTED_AGGREGATION_TYPES.include?(billable_metric.aggregation_type)
      return false if charge.pay_in_advance?
      return false if charge.prorated?
      return false if billable_metric.recurring?

      # `grouped_by` does carry `target_wallet_code`, but the pipeline omits the key entirely
      # for an event carrying no wallet, where Rails always emits it with nil. Reconciling that
      # is not worth its complexity for a shape this rare; revisit if it becomes common.
      return false if charge.accepts_target_wallet

      # The pipeline does not evaluate custom expressions yet.
      billable_metric.expression.blank?
    end
  end
end
