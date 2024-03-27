# frozen_string_literal: true

class MigrateRecurringCountAndUniqueCountAggregation < ActiveRecord::Migration[7.0]
  # NOTE: redefine models to prevent schema issue in the future
  class BillableMetric < ApplicationRecord; end

  class Charge < ApplicationRecord; end

  class Customer < ApplicationRecord; end

  class Event < ApplicationRecord; end

  class Plan < ApplicationRecord; end

  class Subscription < ApplicationRecord; end

  class QuantifiedEvent < ApplicationRecord; end

  def change
    reversible do |dir|
      dir.up do
        # Create quantified event object for all unique count events
        sql = <<-SQL
          SELECT
            events.id AS event_id,
            events.code AS code,
            events.organization_id AS organization_id,
            events.customer_id AS customer_id,
            events.properties AS properties,
            events.timestamp AS event_timestamp,
            subscriptions.external_id AS subscription_external_id,
            billable_metrics.id AS billable_metric_id,
            billable_metrics.field_name AS field_name
          FROM events
          INNER JOIN subscriptions ON subscriptions.id = events.subscription_id
          INNER JOIN billable_metrics ON billable_metrics.code = events.code
          WHERE events.deleted_at IS NULL
            AND events.properties ->> billable_metrics.field_name IS NOT NULL
            AND billable_metrics.aggregation_type = 3
            AND billable_metrics.organization_id = events.organization_id
          ORDER BY event_timestamp ASC;
        SQL

        ApplicationRecord.connection.select_all(sql).each_with_object({}) do |row, _result|
          existing_quantified_event =
            QuantifiedEvent.where(
              customer_id: row["customer_id"],
              billable_metric_id: row["billable_metric_id"],
              external_subscription_id: row["subscription_external_id"],
              external_id: JSON.parse(row["properties"])[row["field_name"].to_s]
            ).where(removed_at: nil).any?

          # There can only be one quantified event for certain external_id which guarantees uniqueness
          next if existing_quantified_event

          quantified_event = QuantifiedEvent.create!(
            customer_id: row["customer_id"],
            billable_metric_id: row["billable_metric_id"],
            external_subscription_id: row["subscription_external_id"],
            external_id: JSON.parse(row["properties"])[row["field_name"].to_s],
            properties: JSON.parse(row["properties"]),
            added_at: row["event_timestamp"]
          )

          event = Event.find_by(id: row["event_id"])
          event.quantified_event_id = quantified_event.id
          event.save!
        end

        # If charge is pay_in_advance and aggregation type is SUM we need to set event metadata since this metadata
        # will be used in calculation of previous_event for further events in same period
        execute <<-SQL
          WITH sum_in_advance_events AS (
            SELECT
              events.id AS event_id,
              events.properties ->> billable_metrics.field_name AS event_value
            FROM events
            INNER JOIN subscriptions ON subscriptions.id = events.subscription_id
            INNER JOIN plans ON plans.id = subscriptions.plan_id
            INNER JOIN charges ON charges.deleted_at IS NULL AND charges.plan_id = plans.id
            INNER JOIN billable_metrics on billable_metrics.code = events.code
            WHERE billable_metrics.organization_id = events.organization_id
              AND events.deleted_at IS NULL
              AND charges.pay_in_advance = TRUE
              AND events.properties ->> billable_metrics.field_name IS NOT NULL
              AND billable_metrics.aggregation_type = 1
          )

          UPDATE events
          SET metadata = jsonb_set(metadata, '{max_aggregation}', to_jsonb(event_value), true) ||
                         jsonb_set(metadata, '{current_aggregation}', to_jsonb(event_value), true)
          FROM sum_in_advance_events
          WHERE sum_in_advance_events.event_id = events.id
        SQL

        # If charge is pay_in_advance and aggregation type is UNIQUE COUNT we need to set event metadata since this
        # metadata will be used in calculation of previous event for further events in the same period
        execute <<-SQL
          WITH unique_count_in_advance_events AS (
            SELECT events.id AS event_id
            FROM events
            INNER JOIN subscriptions ON subscriptions.id = events.subscription_id
            INNER JOIN plans ON plans.id = subscriptions.plan_id
            INNER JOIN charges ON charges.deleted_at IS NULL AND charges.plan_id = plans.id
            INNER JOIN billable_metrics on billable_metrics.code = events.code
            WHERE events.deleted_at IS NULL AND charges.pay_in_advance = TRUE AND billable_metrics.aggregation_type = 3
          )

          UPDATE events
          SET metadata = jsonb_set(metadata, '{max_aggregation}', '1'::jsonb, true) ||
                         jsonb_set(metadata, '{current_aggregation}', '1'::jsonb, true)
          FROM unique_count_in_advance_events
          WHERE unique_count_in_advance_events.event_id = events.id
        SQL
      end
    end
  end
end
