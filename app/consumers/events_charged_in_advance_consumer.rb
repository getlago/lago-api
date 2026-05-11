# frozen_string_literal: true

class EventsChargedInAdvanceConsumer < ApplicationConsumer
  def consume
    messages.each do |message|
      next if message.payload["organization_id"] == ENV["LAGO_SKIPPED_ORGANIZATION_ID"]

      Events::PayInAdvanceJob.set(wait: Events::Stores::ClickhouseStore::CLICKHOUSE_MERGE_DELAY).perform_later(message.payload)
    end
  end
end
