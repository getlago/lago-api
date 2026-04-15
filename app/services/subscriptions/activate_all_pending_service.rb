# frozen_string_literal: true

module Subscriptions
  class ActivateAllPendingService < BaseService
    Result = BaseResult

    def initialize(timestamp:)
      @timestamp = timestamp

      super
    end

    def call
      Subscription
        .joins(customer: :billing_entity)
        .pending
        .where(previous_subscription: nil)
        .where(
          "DATE(subscriptions.subscription_at#{at_time_zone}) <= " \
          "DATE(?#{at_time_zone})",
          Time.zone.at(timestamp)
        )
        .find_each do |subscription|
          ActivateService.call!(subscription:, timestamp: Time.zone.at(timestamp))
        end

      result
    end

    private

    attr_reader :timestamp
  end
end
