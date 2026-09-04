# frozen_string_literal: true

class DeliverEventJob < ApplicationJob
  queue_as :streaming

  unique :until_and_while_executing, on_conflict: :log, lock_ttl: 10.minutes

  EVENT_SERVICES = {
    EventDestinations::CustomerUsage::RefreshedService::EVENT_TYPE =>
      EventDestinations::CustomerUsage::RefreshedService
  }.freeze

  def perform(event_type, object)
    EVENT_SERVICES.fetch(event_type).call(object:)
  end
end
