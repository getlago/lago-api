# frozen_string_literal: false

class CreateEventsAggregatedMv < ActiveRecord::Migration[8.0]
  def change
    sql = <<~SQL
      SELECT
        organization_id,
        code,
        toStartOfHour(timestamp) AS start_at,
        external_subscription_id,
        subscription_id,
        plan_id,
        charge_id,
        charge_filter_id,
        -- COALESCE(grouped_by, map()) AS grouped_by,
        -- Aggregate states based on aggregation type
        CASE
          WHEN aggregation_type = 'sum' THEN sumState(coalesce(decimal_value, 0))
          ELSE sumState(toDecimal128(0, 26))
        END AS sum_state,
        CASE
          WHEN aggregation_type = 'count' THEN countState()
          ELSE countStateIf(false)
        END AS count_state,
        CASE
          WHEN aggregation_type = 'max' THEN maxState(coalesce(decimal_value, 0))
          ELSE maxState(toDecimal128(0, 26))
        END AS max_state,
        CASE
          WHEN aggregation_type = 'latest' THEN argMaxState(coalesce(decimal_value, 0), timestamp)
          ELSE argMaxState(toDecimal128(0, 26), toDateTime64('1970-01-01', 3))
        END AS latest_state
      FROM events_enriched_extended
      WHERE decimal_value IS NOT NULL
        AND subscription_id IS NOT NULL
        AND plan_id IS NOT NULL
        AND charge_id <> ''
      GROUP BY
        organization_id,
        code,
        toStartOfHour(timestamp),
        external_subscription_id,
        subscription_id,
        plan_id,
        charge_id,
        charge_filter_id,
        aggregation_type
    SQL

    create_view :events_aggregated_mv, materialized: true, as: sql, to: "events_aggregated"
  end
end
