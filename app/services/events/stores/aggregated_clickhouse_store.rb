# frozen_string_literal: true

module Events
  module Stores
    class AggregatedClickhouseStore < ClickhouseStore
      NIL_GROUP_VALUE = "<nil>"

      def events(force_from: false, ordered: false)
        # TODO(pre-aggregation): Implement
      end

      def aggregated_events_sql(force_from: false, select: aggregated_arel_table[Arel.star])
        query = aggregated_arel_table.where(
          aggregated_arel_table[:subscription_id].eq(subscription.id)
            .and(aggregated_arel_table[:organization_id].eq(subscription.organization_id)
            .and(aggregated_arel_table[:charge_id].eq(charge_id)
            .and(aggregated_arel_table[:charge_filter_id].eq(charge_filter_id || ""))))
        )

        query = query.where(aggregated_arel_table[:started_at].gteq(from_datetime.beginning_of_minute)) if force_from || use_from_boundary
        query = query.where(aggregated_arel_table[:started_at].lteq(to_datetime)) if to_datetime

        query = if grouped_by_values
          query.where(aggregated_arel_table[:grouped_by].eq(formated_grouped_by_values))
        else
          query.group(aggregated_arel_table[:grouped_by])
        end

        query.project(select).to_sql
      end

      def events_values
        # TODO(pre-aggregation): Implement
      end

      def prorated_events_values(total_duration)
        # TODO(pre-aggregation): Implement
      end

      def last_event
        # TODO(pre-aggregation): Implement
      end

      def grouped_last_event
        # TODO(pre-aggregation): Implement
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

      def grouped_count
        connection_with_retry do |connection|
          sql = aggregated_events_sql(select: [
            cast_to_json(aggregated_arel_table[:grouped_by]),
            to_decimal128(Arel::Nodes::NamedFunction.new(
              "countMerge",
              [aggregated_arel_table[:count_state]]
            )).as("total_count")
          ])

          prepare_grouped_result(connection.select_all(sql).rows)
        end
      end

      # NOTE: check if an event created before the current on belongs to an active (as in present and not removed)
      #       unique property
      def active_unique_property?(event)
        # TODO(pre-aggregation): Implement
      end

      def unique_count
        # TODO(pre-aggregation): Implement
      end

      def unique_count_breakdown
        # TODO(pre-aggregation): Implement
      end

      def prorated_unique_count
        # TODO(pre-aggregation): Implement
      end

      def prorated_unique_count_breakdown(with_remove: false)
        # TODO(pre-aggregation): Implement
      end

      def grouped_unique_count
        # TODO(pre-aggregation): Implement
      end

      def grouped_prorated_unique_count
        # TODO(pre-aggregation): Implement
      end

      def max
        # TODO(pre-aggregation): Implement
      end

      def grouped_max
        # TODO(pre-aggregation): Implement
      end

      def last
        # TODO(pre-aggregation): Implement
      end

      def grouped_last
        # TODO(pre-aggregation): Implement
      end

      def sum_precise_total_amount_cents
        # TODO(pre-aggregation): Implement
      end

      def grouped_sum_precise_total_amount_cents
        # TODO(pre-aggregation): Implement
      end

      def sum
        # TODO(pre-aggregation): Implement
      end

      def grouped_sum
        # TODO(pre-aggregation): Implement
      end

      def prorated_sum(period_duration:, persisted_duration: nil)
        # TODO(pre-aggregation): Implement
      end

      def grouped_prorated_sum(period_duration:, persisted_duration: nil)
        # TODO(pre-aggregation): Implement
      end

      def sum_date_breakdown
        # TODO(pre-aggregation): Implement
      end

      def weighted_sum(initial_value: 0)
        # TODO(pre-aggregation): Implement
      end

      def grouped_weighted_sum(initial_values: [])
        # TODO(pre-aggregation): Implement
      end

      # NOTE: not used in production, only for debug purpose to check the computed values before aggregation
      def weighted_sum_breakdown(initial_value: 0)
        # TODO(pre-aggregation): Implement
      end

      def aggregated_arel_table
        @aggregated_arel_table ||= ::Clickhouse::EventsAggregated.arel_table
      end

      def formated_grouped_by_values
        # NOTE: grouped_by is populated from a sorted Map(String, String) converted into a String
        #       to make it comparable, we need to sort the group keys and replace nil values with "<nil>" string
        grouped_by_values
          .transform_values { |value| value || NIL_GROUP_VALUE }
          .sort_by { |key, _| key }
          .to_h
          .to_json
      end

      # NOTE: returns the values for each groups
      #       The result format will be an array of hash with the format:
      #       [{ groups: { 'cloud' => 'aws', 'region' => 'us_east_1' }, value: 12.9 }, ...]
      def prepare_grouped_result(rows, timestamp: false)
        rows.map do |row|
          group_by_string, value = row

          groups = group_by_string.transform_values! { |v| (v == NIL_GROUP_VALUE) ? nil : v }
          next unless groups.keys.sort == grouped_by.sort

          result = {
            groups: groups,
            value: value
          }

          result
        end
      end

      def to_decimal128(value)
        Arel::Nodes::NamedFunction.new(
          "toDecimal128",
          [
            value,
            DECIMAL_SCALE
          ]
        )
      end

      def cast_to_json(attribute)
        Arel::Nodes::SqlLiteral.new("#{attribute.relation.name}.#{attribute.name}::JSON")
      end
    end
  end
end
