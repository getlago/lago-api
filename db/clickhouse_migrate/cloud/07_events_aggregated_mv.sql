CREATE MATERIALIZED VIEW events_aggregated_mv TO events_aggregated
(
    `organization_id` String,
    `code` String,
    `started_at` DateTime,
    `external_subscription_id` String,
    `subscription_id` String,
    `plan_id` String,
    `charge_id` String,
    `charge_filter_id` String,
    `grouped_by` Map(String, String),
    `precise_total_amount_cents_sum_state` AggregateFunction(sum, Decimal(76, 15)),
    `sum_state` AggregateFunction(sum, Decimal(38, 26)),
    `count_state` AggregateFunction(count),
    `max_state` AggregateFunction(max, Decimal(38, 26)),
    `latest_state` AggregateFunction(argMax, Decimal(38, 26), DateTime64(3))
)
AS SELECT
    organization_id,
    code,
    toStartOfMinute(timestamp) AS started_at,
    external_subscription_id,
    subscription_id,
    plan_id,
    charge_id,
    charge_filter_id,
    sorted_grouped_by AS grouped_by,
    sumState(coalesce(precise_total_amount_cents, toDecimal128(0, 15))) AS precise_total_amount_cents_sum_state,
    multiIf(aggregation_type = 'sum', sumState(coalesce(decimal_value, 0)), sumState(toDecimal128(0, 26))) AS sum_state,
    multiIf(aggregation_type = 'count', countState(), countStateIf(false)) AS count_state,
    multiIf(aggregation_type = 'max', maxState(coalesce(decimal_value, 0)), maxState(toDecimal128(0, 26))) AS max_state,
    multiIf(aggregation_type = 'latest', argMaxState(coalesce(decimal_value, 0), timestamp), argMaxState(toDecimal128(0, 26), toDateTime64('1970-01-01', 3))) AS latest_state
FROM events_enriched_expanded
WHERE (decimal_value IS NOT NULL) AND (subscription_id IS NOT NULL) AND (plan_id IS NOT NULL) AND (charge_id != '')
GROUP BY
    organization_id,
    code,
    toStartOfMinute(timestamp),
    external_subscription_id,
    subscription_id,
    plan_id,
    charge_id,
    charge_filter_id,
    sorted_grouped_by,
    aggregation_type;
