# frozen_string_literal: true

module Events
  module Stores
    class PostgresStore < BaseStore
      def events
        scope = Event.where(external_subscription_id: subscription.external_id)
          .from_datetime(from_datetime)
          .to_datetime(to_datetime)
          .where(code:)
          .order(timestamp: :asc)

        if numeric_property
          scope = scope.where(presence_condition)
            .where(numeric_condition)
        end

        return scope unless group

        group_scope(scope)
      end

      def events_values
        field_name = sanitized_propery_name
        field_name = "(#{field_name})::numeric" if numeric_property

        events.pluck(Arel.sql(field_name))
      end

      def max
        events.maximum("(#{sanitized_propery_name})::numeric")
      end

      def last
        events.reorder(timestamp: :desc, created_at: :desc).first
      end

      private

      def group_scope(scope)
        scope = scope.where('events.properties @> ?', { group.key.to_s => group.value }.to_json)
        return scope unless group.parent

        scope.where('events.properties @> ?', { group.parent.key.to_s => group.parent.value }.to_json)
      end

      def sanitized_propery_name
        ActiveRecord::Base.sanitize_sql_for_conditions(
          ['events.properties->>?', aggregation_property],
        )
      end

      def presence_condition
        "events.properties::jsonb ? '#{ActiveRecord::Base.sanitize_sql_for_conditions(aggregation_property)}'"
      end

      def numeric_condition
        # NOTE: ensure property value is a numeric value
        "#{sanitized_propery_name} ~ '^-?\\d+(\\.\\d+)?$'"
      end
    end
  end
end
