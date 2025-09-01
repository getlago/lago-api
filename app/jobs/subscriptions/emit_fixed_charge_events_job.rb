# frozen_string_literal: true

module Subscriptions
  class EmitFixedChargeEventsJob < ApplicationJob
    queue_as "default"

    def perform(subscriptions:, timestamp: Time.current.to_i)
      Subscriptions::EmitFixedChargeEventsService.call!(
        subscriptions:,
        timestamp: Time.zone.at(timestamp)
      )
    end
  end
end
