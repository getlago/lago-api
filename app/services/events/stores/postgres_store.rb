# frozen_string_literal: true

module Events
  module Stores
    class PostgresStore < BaseStore
      def events
        # TODO: switch to external_subscription_id to allow events sent before subscription creation
        scope = Event.where(subscription_id: subscription.id)
          .from_datetime(from_datetime)
          .to_datetime(to_datetime)
          .where(code:)
          .order(timestamp: :asc)
        return scope unless group

        group_scope(scope)
      end

      private

      def group_scope(scope)
        scope = scope.where('events.properties @> ?', { group.key.to_s => group.value }.to_json)
        return scope unless group.parent

        scope.where('events.properties @> ?', { group.parent.key.to_s => group.parent.value }.to_json)
      end
    end
  end
end
