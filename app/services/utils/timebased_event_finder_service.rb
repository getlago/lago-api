# frozen_string_literal: true

module Utils
  class TimebasedEventFinderService < BaseService
    def initialize(subscription:, timestamp:)
      super(nil)
      @subscription = subscription
      @timestamp = timestamp
    end

    def latest_timebased_event
      @latest_timebased_event ||= find_latest_timebased_event
    end

    private

    attr_accessor :subscription, :timestamp

    delegate :organization, to: :subscription

    def find_latest_timebased_event
      TimebasedEvent
        .where(organization:)
        .where(external_subscription_id: subscription.external_id)
        .where('timestamp <= ?', timestamp)
        .order(timestamp: :desc)
        .first
    end
  end
end
