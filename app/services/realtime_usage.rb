# frozen_string_literal: true

# Shared by the event store provider, the charge cache gate and the parity task, which must
# agree on what the buckets can answer.
module RealtimeUsage
  SUPPORTED_AGGREGATION_TYPES = %w[count_agg sum_agg max_agg latest_agg].freeze

  BUCKET_DURATION = 15.minutes

  # What the ClickHouse driver raises on a connection it cannot use, plus the two errors the
  # retry helper and the row mapping raise on their own.
  READ_ERRORS = [
    *Events::Stores::Utils::ClickhouseConnection::RETRYABLE_ERRORS,
    Events::Stores::Clickhouse::MemoryLimitError,
    JSON::ParserError
  ].freeze

  # percentage and custom walk individual events. dynamic reads the precise amounts the buckets
  # sum on sum rows, the only aggregation type a dynamic charge accepts.
  SUPPORTED_CHARGE_MODELS = %w[standard graduated package volume graduated_percentage dynamic].freeze

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

    # On top of enabled?, so recurring sums roll back on their own without turning off the buckets
    # for the organization's other charges. The forced gate leaves it closed: the bucket store does
    # not answer the recurring delta yet, so the parity task would compare the events with themselves.
    def recurring_sum_enabled?(organization)
      organization.feature_flag_enabled?(:realtime_usage_recurring_sum)
    end

    def floor_to_bucket(time)
      Time.zone.at(time.to_i - (time.to_i % BUCKET_DURATION.to_i))
    end

    # A bucket is summed whole, so an end inside one widens to the wall after it rather than
    # cutting the bucket.
    def ceil_to_bucket(time)
      floor = floor_to_bucket(time)

      (floor == time) ? floor : floor + BUCKET_DURATION
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
      # Within the supported aggregation types, only sum_agg can be recurring. The metric's
      # organization is the one usage callers preload.
      return "recurring_metric" if billable_metric.recurring? && !recurring_sum_enabled?(billable_metric.organization)

      nil
    end

    # Buckets written before a charge accepted a target wallet hold no wallet code, so their usage
    # would be debited from the wrong wallet. Nothing records that switch, so any edit counts.
    def wallet_charge_changed_since?(charge, datetime)
      charge.accepts_target_wallet && charge.updated_at > datetime
    end
  end
end
