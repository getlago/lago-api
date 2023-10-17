# frozen_string_literal: true

class FillCachedAggregations < ActiveRecord::Migration[7.0]
  class CachedAggregation < ApplicationRecord; end

  class Group < ApplicationRecord
    belongs_to :parent, class_name: 'Group', foreign_key: 'parent_group_id'
    has_many :children, class_name: 'Group', foreign_key: 'parent_group_id'
  end

  class BillableMetric < ApplicationRecord
    has_many :groups
  end

  def change
    reversible do |dir|
      dir.up do
        sql = <<-SQL
          WITH ordered_billable_metric AS (
            SELECT
              *,
              ROW_NUMBER() OVER (
                PARTITION BY billable_metrics.code
                ORDER BY billable_metrics.deleted_at DESC NULLS FIRST
              ) AS row_number
            FROM billable_metrics
          ),
          last_billable_metrics AS (
              SELECT
                ordered_billable_metric.id,
                ordered_billable_metric.organization_id,
                ordered_billable_metric.code,
                COUNT(groups.id) AS group_count
              FROM ordered_billable_metric
                LEFT JOIN groups ON ordered_billable_metric.id = groups.billable_metric_id
              WHERE ordered_billable_metric.row_number = 1
              GROUP BY
                ordered_billable_metric.id,
                ordered_billable_metric.organization_id,
                ordered_billable_metric.code
          )

          SELECT
            events.id AS event_id,
            events.timestamp,
            events.external_subscription_id,
            events.organization_id,
            last_billable_metrics.id AS billable_metric_id,
            last_billable_metrics.group_count AS group_count,
            events.properties,
            events.metadata->>'current_aggregation',
            events.metadata->>'max_aggregation',
            events.metadata->>'max_aggregation_with_proration',
            events.created_at
          FROM events
            INNER JOIN last_billable_metrics
              ON last_billable_metrics.organization_id = events.organization_id
              AND last_billable_metrics.code = events.code
          WHERE
            events.metadata->>'current_aggregation' IS NOT NULL
            OR events.metadata->>'max_aggregation' IS NOT NULL
            OR events.metadata->>'max_aggregation_with_proration' IS NOT NULL
        SQL

        records = ActiveRecord::Base.connection.exec_query(sql)
        records.each do |event|
          if event['group_count'].zero?
            CachedAggregation.create_with(
              timestamp: event['timestamp'],
              current_aggregation: event['current_aggregation'],
              max_aggregation: event['max_aggregation'],
              max_aggregation_with_proration: event['max_aggregation_with_proration'],
            ).find_or_create_with(
              organization_id: event['organization_id'],
              event_id: event['event_id'],
              group_id: nil,
              external_subscription_id: event['external_subscription_id'],
              billable_metric_id: event['billable_metric_id'],
            )
          else
            billable_metric = BillableMetric.find_by(id: event['billable_metric_id'])
            next unless billable_metric

            billable_metric.groups.where(parent_id: nil).find_each do |group|
              next unless JSON.parse(event['properties'])[group.key][group.value]

              if group.children.any?
                group.children.find_each do |child|
                  next unless JSON.parse(event['properties'])[child.key][child.value]

                  CachedAggregation.create_with(
                    timestamp: event['timestamp'],
                    current_aggregation: event['current_aggregation'],
                    max_aggregation: event['max_aggregation'],
                    max_aggregation_with_proration: event['max_aggregation_with_proration'],
                  ).find_or_create_with(
                    organization_id: event['organization_id'],
                    event_id: event['event_id'],
                    group_id: child.id,
                    external_subscription_id: event['external_subscription_id'],
                    billable_metric_id: event['billable_metric_id'],
                  )
                end
              else
                CachedAggregation.create_with(
                  timestamp: event['timestamp'],
                  current_aggregation: event['current_aggregation'],
                  max_aggregation: event['max_aggregation'],
                  max_aggregation_with_proration: event['max_aggregation_with_proration'],
                ).find_or_create_with(
                  organization_id: event['organization_id'],
                  event_id: event['event_id'],
                  group_id: group.id,
                  external_subscription_id: event['external_subscription_id'],
                  billable_metric_id: event['billable_metric_id'],
                )
              end
            end
          end
        end
      end
    end
  end
end
