# frozen_string_literal: true

module Events
  module Stores
    class ClickhouseStore < BaseStore
      # NOTE: keeps in mind that events could contains duplicated transaction_id
      #       and should be deduplicated depending on the aggregation logic
      def events
        scope = Clickhouse::EventsRaw.where(external_subscription_id: subscription.external_id)
          .where('events_raw.timestamp >= ?', from_datetime)
          .where('events_raw.timestamp <= ?', to_datetime)
          .where(code:)
          .order(timestamp: :asc)

        return scope unless group

        scope
      end

      def count
        sql = events.select('COUNT(DISTINCT(events_raw.transaction_id)) AS events_count').to_sql
        Clickhouse::EventsRaw.connection.select_value(sql).to_i
      end

      private

      def group_scope(scope)
        scope.where('events_raw.properties[?] = ?', group.key.to_s, group.value.to_s)
        return scope unless group.parent

        scope.where('events_raw.properties[?] = ?', group.parent.key.to_s => group.parent.value.to_s)
      end
    end
  end
end
