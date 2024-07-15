# frozen_string_literal: false

class CreateEventsMaxAggMv < ActiveRecord::Migration[7.1]
  def change
    sql = <<-SQL
    SELECT
      organization_id,
      external_subscription_id,
      code,
      charge_id,
      maxState(toDecimal128(coalesce(value, '0'), 26)) as value,
      toStartOfHour(timestamp) as timestamp,
      filters,
      grouped_by
    FROM events_enriched
    WHERE aggregation_type = 'max_agg'
    GROUP BY
      organization_id,
      external_subscription_id,
      code,
      charge_id,
      toStartOfHour(timestamp) as timestamp,
      filters,
      grouped_by
    SQL

    create_view :events_max_agg_mv, materialized: true, as: sql, to: 'events_max_agg'
  end
end
