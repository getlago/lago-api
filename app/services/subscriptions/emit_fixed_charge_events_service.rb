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
          next if fixed_charge_already_emitted?(subscription, fixed_charge)

          ::FixedChargeEvents::CreateService.call!(
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

    def applicable_timezone
      subscriptions.first.customer.applicable_timezone
    end

    def fixed_charge_already_emitted?(subscription, fixed_charge)
      return false unless timestamp

      FixedChargeEvent
        .where(subscription:, fixed_charge:)
        .where(
          "DATE(fixed_charge_events.timestamp AT TIME ZONE ?) = DATE(? AT TIME ZONE ?)",
          applicable_timezone, timestamp, applicable_timezone
        )
        .exists?
    end
  end
end
