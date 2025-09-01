# frozen_string_literal: true

module Subscriptions
  class EmitFixedChargeEventsService < BaseService
    def initialize(subscriptions:, timestamp: Time.current)
      @subscriptions = subscriptions
      @timestamp = timestamp
      super
    end

    def call
      subscriptions.each do |subscription|
        subscription.fixed_charges.find_each do |fixed_charge|
          FixedCharges::EmitFixedChargeEventService.call(
            subscription:,
            fixed_charge:,
            timestamp:
          )
        end
      end

      result
    end

    private

    attr_reader :subscriptions, :timestamp
  end
end
