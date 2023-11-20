# frozen_string_literal: true

module Events
  module Stores
    class ClickhouseStore < BaseStore
      DECIMAL_SCALE = 26

      # NOTE: keeps in mind that events could contains duplicated transaction_id
      #       and should be deduplicated depending on the aggregation logic
      def events
        scope = Clickhouse::EventsRaw.where(external_subscription_id: subscription.external_id)
          .where('events_raw.timestamp >= ?', from_datetime)
          .where('events_raw.timestamp <= ?', to_datetime)
          .where(code:)
          .order(timestamp: :asc)

        scope = scope.where(numeric_condition) if numeric_property

        return scope unless group

        scope
      end

      def events_values
        events
          .group('events_raw.transaction_id, events_raw.properties, events_raw.timestamp')
          .pluck(Arel.sql(
            ActiveRecord::Base.sanitize_sql_for_conditions(
              ['toDecimal128(events_raw.properties[?], ?)', aggregation_property, DECIMAL_SCALE],
            ),
          ))
      end

      def count
        sql = events.reorder(:transaction_id).group(:transaction_id)
          .select('COUNT(DISTINCT(events_raw.transaction_id)) AS events_count').to_sql

        Clickhouse::EventsRaw.connection.select_value(sql).to_i
      end

      def max
        events.maximum(
          Arel.sql(
            ActiveRecord::Base.sanitize_sql_for_conditions(
              ['toDecimal128(events_raw.properties[?], ?)', aggregation_property, DECIMAL_SCALE],
            ),
          ),
        )
      end

      delegate :last, to: :events

      private

      def group_scope(scope)
        scope.where('events_raw.properties[?] = ?', group.key.to_s, group.value.to_s)
        return scope unless group.parent

        scope.where('events_raw.properties[?] = ?', group.parent.key.to_s => group.parent.value.to_s)
      end

      def numeric_condition
        ActiveRecord::Base.sanitize_sql_for_conditions(
          [
            'toDecimal128OrNull(events_raw.properties[?], ?) IS NOT NULL',
            aggregation_property,
            DECIMAL_SCALE,
          ],
        )
      end
    end
  end
end
