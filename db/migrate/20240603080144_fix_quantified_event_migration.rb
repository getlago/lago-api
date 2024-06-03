# frozen_string_literal: true

class FixQuantifiedEventMigration < ActiveRecord::Migration[7.0]
  class QuantifiedEvent < ApplicationRecord; end

  class CachedAggregation < ApplicationRecord; end

  def change
    sql = <<~SQL
      SELECT
        quantified_events.*,
        charges.id AS charge_id
      FROM quantified_events
        INNER JOIN billable_metrics on quantified_events.billable_metric_id = billable_metrics.id
        INNER JOIN charges on billable_metrics.id = charges.billable_metric_id
        INNER JOIN plans on charges.plan_id = plans.id
        INNER JOIN subscriptions ON subscriptions.external_id = quantified_events.external_subscription_id
          AND subscriptions.plan_id = plans.id
      WHERE
        billable_metrics.aggregation_type = 5
        AND subscriptions.started_at <= quantified_events.added_at
        AND (
          subscriptions.terminated_at IS NULL
          OR subscriptions.terminated_at >= quantified_events.added_at
        )
    SQL

    QuantifiedEvent.find_by_sql(sql).each do |quantified_event|
      CachedAggregation.find_or_create_by!(
        organization_id: quantified_event.organization_id,
        charge_id: quantified_event.charge_id,
        timestamp: quantified_event.added_at,
        external_subscription_id: quantified_event.external_subscription_id,
        charge_filter_id: quantified_event.charge_filter_id,
        current_aggregation: BigDecimal(quantified_event.properties['total_aggregated_units'] || '0'),
        grouped_by: quantified_event.grouped_by,
        created_at: quantified_event.created_at,
        updated_at: quantified_event.updated_at
      )
    end
  end
end
