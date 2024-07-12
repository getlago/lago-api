# frozen_string_literal: false

class CreateEventsCountAggMv < ActiveRecord::Migration[7.1]
  def change
    sql = <<-SQL
    SELECT
      organization_id,
      external_subscription_id,
      code,
      charge_id,
      sum(toDecimal128(value, 26)) as value,
      toStartOfHour(timestamp) as timestamp,
      filters,
      grouped_by
    FROM events_enriched
    WHERE aggregation_type = 'count_agg'
    GROUP BY
      organization_id,
      external_subscription_id,
      code,
      charge_id,
      toStartOfHour(timestamp) as timestamp,
      filters,
      grouped_by
    SQL

    create_view :events_count_agg_mv, materialized: true, as: sql, to: 'events_count_agg'
  end
end
