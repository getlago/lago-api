# frozen_string_literal: true

class EventsChargedInAdvanceConsumer < ApplicationConsumer
  # Give clickhouse the time to consume and merge the event processed on the events processor side
  CLICKHOUSE_MERGE_DELAY = 15.seconds

  def consume
    messages.each do |message|
      Events::PayInAdvanceJob.set(wait: CLICKHOUSE_MERGE_DELAY).perform_later(message.payload)
    end
  end
end
