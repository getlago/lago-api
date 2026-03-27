# frozen_string_literal: true

class EventsChargedInAdvanceConsumer < ApplicationConsumer
  CHARGE_CACHE_EXPIRATION_DELAY = 15.seconds

  def consume
    messages.each do |message|
      Events::PayInAdvanceJob.set(wait: CHARGE_CACHE_EXPIRATION_DELAY).perform_later(message.payload)
    end
  end
end
