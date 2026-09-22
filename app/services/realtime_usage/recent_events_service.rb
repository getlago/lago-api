# frozen_string_literal: true

module RealtimeUsage
  # Whether the subscription received events since the given time, read from the events store the
  # organization bills on. A difference found while events keep arriving is a race, not a divergence.
  class RecentEventsService < BaseService
    Result = BaseResult[:received]

    def initialize(subscription:, since:)
      @subscription = subscription
      @since = since

      super
    end

    def call
      result.received = events_class
        .where(
          organization_id: subscription.organization_id,
          external_subscription_id: subscription.external_id,
          timestamp: since..
        )
        .exists?
      result
    end

    private

    attr_reader :subscription, :since

    def events_class
      subscription.organization.clickhouse_events_store? ? Clickhouse::EventsEnriched : Event
    end
  end
end
