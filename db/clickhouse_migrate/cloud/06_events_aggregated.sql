CREATE TABLE events_aggregated
(
    `organization_id` String,
    `code` String,
    `started_at` DateTime64(3),
    `external_subscription_id` String,
    `subscription_id` String,
    `plan_id` String,
    `charge_id` String,
    `charge_filter_id` String DEFAULT '',
    `grouped_by` String,
    `precise_total_amount_cents_sum_state` AggregateFunction(sum, Decimal(40, 15)),
    `sum_state` AggregateFunction(sum, Decimal(38, 26)),
    `count_state` AggregateFunction(count, UInt64),
    `max_state` AggregateFunction(max, Decimal(38, 26)),
    `latest_state` AggregateFunction(argMax, Decimal(38, 26), DateTime64(3)),
    `aggregated_at` DateTime64(3) DEFAULT now()
)
ENGINE = SharedMergeTree('/clickhouse/tables/{uuid}/{shard}', '{replica}')
ORDER BY (organization_id, code, started_at, external_subscription_id, subscription_id, charge_id, charge_filter_id, grouped_by)
SETTINGS index_granularity = 8192;
