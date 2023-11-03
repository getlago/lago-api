# frozen_string_literal: true

class FillCachedAggregations < ActiveRecord::Migration[7.0]
  class Subscription < ApplicationRecord; end
  class Event < ApplicationRecord; end
  class CachedAggregation < ApplicationRecord; end

  class Group < ApplicationRecord
    belongs_to :parent, class_name: 'Group', foreign_key: 'parent_group_id'
    has_many :children, class_name: 'Group', foreign_key: 'parent_group_id'
  end

  class BillableMetric < ApplicationRecord
    has_many :groups
  end

  class Charge < ApplicationRecord; end

  def change
    reversible do |dir|
      dir.up do
        sql = <<-SQL
          SELECT *
          FROM events
          WHERE (
            events.metadata->>'current_aggregation' IS NOT NULL
            OR events.metadata->>'max_aggregation' IS NOT NULL
            OR events.metadata->>'max_aggregation_with_proration' IS NOT NULL
          )
          AND events.deleted_at IS NULL
        SQL

        Event.find_by_sql([sql]).each do |event|
          subscription = Subscription
            .joins('INNER JOIN customers ON customers.id = subscriptions.customer_id')
            .where('customers.organization_id = ?', event.organization_id)
            .where("date_trunc('second', started_at::timestamp) <= ?::timestamp", event.timestamp)
            .where(
              "terminated_at IS NULL OR date_trunc('second', terminated_at::timestamp) >= ?",
              event.timestamp,
            )
            .order('terminated_at DESC NULLS FIRST, started_at DESC')
            .first
          next unless subscription

          billable_metric = BillableMetric
            .where(organization_id: event.organization_id)
            .where(code: event.code)
            .where(
              'billable_metrics.deleted_at IS NULL OR deleted_at > ?', event.timestamp
            )
            .where('billable_metrics.created_at < ?', event.timestamp)
            .order('billable_metrics.deleted_at DESC NULLS FIRST')
            .first
          next unless billable_metric

          charges = Charge.where(plan_id: subscription.plan_id)
            .where(billable_metric_id: billable_metric.id)

          charges.each do |charge|
            # NOTE: billable metric without groups
            parent_groups = billable_metric.groups.where(parent_group_id: nil).to_a

            if parent_groups.count.zero?
              CachedAggregation.create_with(
                timestamp: event.timestamp,
                current_aggregation: event.metadata['current_aggregation'],
                max_aggregation: event.metadata['max_aggregation'],
                max_aggregation_with_proration: event.metadata['max_aggregation_with_proration'],
              ).find_or_create_with(
                organization_id: event.organization_id,
                event_id: event.id,
                group_id: nil,
                external_subscription_id: event.external_subscription_id,
                charge_id: charge.id,
              )
            else
              parent_groups.each do |group|
                next unless event.properties[group.key] == group.value

                child_group = group.children.all

                if child_group.any?
                  child_group.each do |child|
                    next unless event.properties[child.key] == child.value

                    CachedAggregation.create_with(
                      timestamp: event.timestamp,
                      current_aggregation: event.metadata['current_aggregation'],
                      max_aggregation: event.metadata['max_aggregation'],
                      max_aggregation_with_proration: event.metadata['max_aggregation_with_proration'],
                    ).find_or_create_with(
                      organization_id: event.organization_id,
                      event_id: event.id,
                      group_id: child.id,
                      external_subscription_id: event.external_subscription_id,
                      charge_id: charge.id,
                    )
                  end
                else
                  CachedAggregation.create_with(
                    timestamp: event.timestamp,
                    current_aggregation: event.metadata['current_aggregation'],
                    max_aggregation: event.metadata['max_aggregation'],
                    max_aggregation_with_proration: event.metadata['max_aggregation_with_proration'],
                  ).find_or_create_with(
                    organization_id: event.organization_id,
                    event_id: event.id,
                    group_id: group.id,
                    external_subscription_id: event.external_subscription_id,
                    charge_id: charge.id,
                  )
                end
              end
            end
          end
        end
      end
    end
  end
end
