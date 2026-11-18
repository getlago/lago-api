# frozen_string_literal: true

# The product events pipeline's counterpart of EventsChargedInAdvanceConsumer. Its events are
# keyed by contract, which the pay in advance path reads as external_subscription_id, as it does
# for every product catalog event (Events::CreateService).
class ProductEventsChargedInAdvanceConsumer < ApplicationConsumer
  def consume
    messages.each do |message|
      payload = message.payload
      event = payload.except("external_contract_id").merge("external_subscription_id" => payload["external_contract_id"])

      Events::PayInAdvanceJob.set(wait: Events::Stores::ClickhouseStore::CLICKHOUSE_MERGE_DELAY).perform_later(event)
    end
  end
end
