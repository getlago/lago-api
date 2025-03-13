# frozen_string_literal: true

class EventsChargedInAdvanceConsumer < ApplicationConsumer
  def consume
    messages.each do |message|
      Events::PayInAdvanceJob.perform_later(message.payload)
    end
  end
end
