# frozen_string_literal: true

# Gating for the realtime usage read path (RisingWave-fed 15-minute usage
# buckets in ClickHouse, Clickhouse::UsageBucket). Scope is deliberately
# narrow while the pipeline is being proven: count/sum, in arrears,
# non-prorated, non-recurring, no custom expression. Everything else keeps
# the events-store (raw events) aggregation path.
#
# count and sum are also the aggregations that recompose losslessly across
# buckets; unique_count does not (distinct across buckets != sum of
# per-bucket distincts) and will need its own structure.
module RealtimeUsage
  BUCKET_INTERVAL_MINUTES = 15

  module_function

  def enabled?
    ENV["LAGO_RISINGWAVE_USAGE_ENABLED"] == "true"
  end

  # Floors a period boundary down to its bucket wall, so a window that starts
  # mid-bucket still includes the bucket holding its first events.
  #
  # Period boundaries land on bucket walls for every real timezone (offsets are
  # multiples of 15 minutes), so the floor is exact except for subscriptions
  # starting or terminating at a mid-bucket time, which share at most 15 minutes
  # of events with the neighbour period.
  def bucket_floor(time)
    # Time#change resets sec/usec cascadingly below :min.
    time&.change(min: time.min - time.min % BUCKET_INTERVAL_MINUTES)
  end

  def eligible_charge?(charge)
    return false unless enabled?
    return false if charge.pay_in_advance?
    return false if charge.prorated?

    billable_metric = charge.billable_metric
    return false if billable_metric.recurring?
    return false if billable_metric.expression.present?

    %w[count_agg sum_agg].include?(billable_metric.aggregation_type)
  end
end
