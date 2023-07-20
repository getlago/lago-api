# frozen_string_literal: true

class MigrateRecurringCountAndUniqueCountAggregation < ActiveRecord::Migration[7.0]
  # NOTE: redefine models to prevent schema issue in the future
  class BillableMetric < ApplicationRecord; end
  class Charge < ApplicationRecord; end
  class Customer < ApplicationRecord; end
  class Event < ApplicationRecord; end
  class Plan < ApplicationRecord; end
  class Subscription < ApplicationRecord; end

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
            subscriptions.external_id AS subscription_external_id
          FROM events
          INNER JOIN subscriptions ON subscriptions.id = events.subscription_id
          INNER JOIN billable_metrics ON billable_metrics.code = events.code
          WHERE events.deleted_at IS NULL AND billable_metrics.aggregation_type = 3
          ORDER BY event_timestamp ASC;
        SQL

        ApplicationRecord.connection.select_all(sql).each_with_object({}) do |row, _result|
          matching_billable_metric = BillableMetric.find_by(
            code: row['code'],
            organization_id: row['organization_id'],
          )

          existing_quantified_event =
            QuantifiedEvent.where(
              customer_id: row['customer_id'],
              billable_metric_id: matching_billable_metric.id,
              external_subscription_id: row['subscription_external_id'],
              external_id: JSON.parse(row['properties'])[matching_billable_metric.field_name.to_s],
            ).where(removed_at: nil).any?

          # There can only be one quantified event for certain external_id which guarantees uniqueness
          next if existing_quantified_event

          quantified_event = QuantifiedEvent.create!(
            customer_id: row['customer_id'],
            billable_metric_id: matching_billable_metric.id,
            external_subscription_id: row['subscription_external_id'],
            external_id: JSON.parse(row['properties'])[matching_billable_metric.field_name.to_s],
            properties: JSON.parse(row['properties']),
            added_at: row['event_timestamp'],
          )

          event = Event.find_by(id: row['event_id'])
          event.quantified_event_id = quantified_event.id
          event.save!
        end

        # All charges that are related to recurring_count_agg should be prorated = true
        sql = <<-SQL
          SELECT
            charges.id AS charge_id
          FROM charges
          INNER JOIN billable_metrics ON billable_metrics.id = charges.billable_metric_id
          WHERE billable_metrics.aggregation_type = 4;
        SQL
        ApplicationRecord.connection.select_all(sql).each_with_object({}) do |row, _result|
          charge = Charge.find_by(id: row['charge_id'])
          charge.prorated = true
          # Skipping validations since prorated is not allowed for graduated charge model, but we want to allow
          # it for old charges where we will keep old calculation
          charge.save!(validate: false)
        end

        # Recurring count agg billable metrics should be recurring = true and aggregation type should be unique count
        sql = <<-SQL
          SELECT
            billable_metrics.id AS billable_metric_id
          FROM billable_metrics
          WHERE billable_metrics.aggregation_type = 4;
        SQL
        ApplicationRecord.connection.select_all(sql).each_with_object({}) do |row, _result|
          billable_metric = BillableMetric.find_by(id: row['billable_metric_id'])
          billable_metric.recurring = true
          billable_metric.aggregation_type = 3 # Setting unique count aggregation
          billable_metric.save!
        end

        # If charge is pay_in_advance and aggregation type is SUM we need to set event metadata since this metadata
        # will be used in calculation of previous_event for further events in same period
        sql = <<-SQL
          SELECT
            events.id AS event_id,
            events.code AS code,
            events.organization_id AS organization_id,
            events.customer_id AS customer_id,
            events.properties AS properties,
            events.timestamp AS event_timestamp,
            subscriptions.external_id AS subscription_external_id
          FROM events
          INNER JOIN subscriptions ON subscriptions.id = events.subscription_id
          INNER JOIN plans ON plans.id = subscriptions.plan_id
          INNER JOIN charges ON charges.deleted_at IS NULL AND charges.plan_id = plans.id
          INNER JOIN billable_metrics on billable_metrics.code = events.code
          WHERE events.deleted_at IS NULL AND charges.pay_in_advance = TRUE AND billable_metrics.aggregation_type = 1;
        SQL
        ApplicationRecord.connection.select_all(sql).each_with_object({}) do |row, _result|
          billable_metric = BillableMetric.find_by(
            code: row['code'],
            organization_id: row['organization_id'],
          )

          event = Event.find_by(id: row['event_id'])
          value = event.properties.fetch(billable_metric.field_name, 0).to_s
          event.metadata['current_aggregation'] = value
          event.metadata['max_aggregation'] = value
          event.save!
        end

        # If charge is pay_in_advance and aggregation type is UNIQUE COUNT we need to set event metadata since this
        # metadata will be used in calculation of previous event for further events in the same period
        sql = <<-SQL
          SELECT
            events.id AS event_id,
            events.code AS code,
            events.organization_id AS organization_id,
            events.customer_id AS customer_id,
            events.properties AS properties,
            events.timestamp AS event_timestamp,
            subscriptions.external_id AS subscription_external_id
          FROM events
          INNER JOIN subscriptions ON subscriptions.id = events.subscription_id
          INNER JOIN plans ON plans.id = subscriptions.plan_id
          INNER JOIN charges ON charges.deleted_at IS NULL AND charges.plan_id = plans.id
          INNER JOIN billable_metrics on billable_metrics.code = events.code
          WHERE events.deleted_at IS NULL AND charges.pay_in_advance = TRUE AND billable_metrics.aggregation_type = 3;
        SQL
        ApplicationRecord.connection.select_all(sql).each_with_object({}) do |row, _result|
          event = Event.find_by(id: row['event_id'])
          event.metadata['current_aggregation'] = 1
          event.metadata['max_aggregation'] = 1
          event.save!
        end
      end
    end
  end
end
