# frozen_string_literal: true

module Events
  module Stores
    class AggregatedClickhouseStore < ClickhouseStore
      def events(force_from: false, ordered: false)
        with_retry do
          scope = ::Clickhouse::EventsEnrichedExpanded.where(external_subscription_id: subscription.external_id)
            .where(organization_id: subscription.organization.id)
            .where(charge_id: charge_id)
            .where(charge_filter_id: charge_filter_id)

          # TODO: grouped by

          scope = scope.order(timestamp: :asc) if ordered

          scope = scope.where("events_enriched_expanded.timestamp >= ?", from_datetime) if force_from || use_from_boundary
          scope = scope.where("events_enriched_expanded.timestamp <= ?", to_datetime) if to_datetime
          scope = scope.limit_by(1, "events_enriched_expanded.transaction_id")

          scope = apply_grouped_by_values(scope) if grouped_by_values?
          scope
        end
      end

      def aggregated_events_sql(force_from: false, ordered: false, select: aggregated_arel_table[Arel.star])
        query = aggregated_arel_table.where(
          aggregated_arel_table[:external_subscription_id].eq(subscription.external_id)
            .and(aggregated_arel_table[:organization_id].eq(subscription.organization_id)
            .and(aggregated_arel_table[:charge_id].eq(charge_id)
            .and(aggregated_arel_table[:charge_filter_id].eq(charge_filter_id))))
        )

        # TODO: make sure we are good with the boundaries
        query = query.order(aggregated_arel_table[:started_at].desc) if ordered
        query = query.where(aggregated_arel_table[:started_at].gteq(from_datetime)) if force_from || use_from_boundary
        query = query.where(aggregated_arel_table[:started_at].lteq(to_datetime)) if to_datetime

        # TODO: group by

        query.project(select).to_sql
      end

      def count
        connection_with_retry do |connection|
          sql = aggregated_events_sql(select: [
            Arel::Nodes::NamedFunction.new(
              "countMerge",
              [aggregated_arel_table[:count_state]]
            ).as("total_count")
          ])

          connection.select_value(sql).to_i
        end
      end

      def max
        connection_with_retry do |connection|
          sql = aggregated_events_sql(select: [
            Arel::Nodes::NamedFunction.new(
              "maxMerge",
              [aggregated_arel_table[:count_state]]
            ).as("total_sum")
          ])

          connection.select_value(sql)
        end
      end

      def sum
        connection_with_retry do |connection|
          sql = aggregated_events_sql(select: [
            Arel::Nodes::NamedFunction.new(
              "sumMerge",
              [aggregated_arel_table[:count_state]]
            ).as("max_value")
          ])

          connection.select_value(sql)
        end
      end

      private

      def aggregated_arel_table
        @aggregated_arel_table ||= ::Clickhouse::EventsAggregated.arel_table
      end
    end
  end
end
