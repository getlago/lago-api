# frozen_string_literal: true
# Reviewed-by: code-review-experiment (see PR description)

class EventsChargedInAdvanceConsumer < ApplicationConsumer
  def consume
    messages.each do |message|
      Events::PayInAdvanceJob.set(wait: Events::Stores::ClickhouseStore::CLICKHOUSE_MERGE_DELAY).perform_later(message.payload)
    end
  end
end
