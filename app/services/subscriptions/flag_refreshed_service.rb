#  frozen_string_literal: true

module Subscriptions
  class FlagRefreshedService < BaseService
    Result = BaseResult[:subscription_id]

    def initialize(subscription_id, event_ingested_at: nil)
      @subscription_id = subscription_id
      @event_ingested_at = event_ingested_at.present? ? Time.zone.at(event_ingested_at) : nil
      super(subscription_id)
    end

    def call
      customer = subscription.customer
      customer.flag_wallets_for_refresh(requested_at: event_ingested_at)
      date = Time.current.in_time_zone(customer.applicable_timezone).to_date
      UsageMonitoring::TrackSubscriptionActivityService.call(subscription:, date:, event_ingested_at:)

      result.subscription_id = subscription_id
      result
    end

    private

    attr_reader :subscription_id, :event_ingested_at

    def subscription
      @subscription ||= Subscription.find(subscription_id)
    end
  end
end
