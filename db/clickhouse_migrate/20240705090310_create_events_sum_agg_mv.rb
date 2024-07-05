# frozen_string_literal: false

class CreateEventsSumAggMv < ActiveRecord::Migration[7.1]
  def change
    sql = <<-SQL
    SELECT
      organization_id,
      external_subscription_id,
      code,
      charge_id,
      sum(toDecimal128(value, 26)) as value,
      toStartOfHour(timestamp) as timestamp
    FROM events_enriched
    WHERE aggregation_type = 'sum_agg'
    GROUP BY
      organization_id,
      external_subscription_id,
      code,
      charge_id,
      toStartOfHour(timestamp) as timestamp
    SQL

    create_view :events_sum_agg_mv, materialized: true, as: sql, to: 'events_sum_agg'
  end
end
