# frozen_string_literal: true

class DeliverEventJob < ApplicationJob
  queue_as :streaming

  ON_CONFLICT = lambda do |job|
    EventDestinations::DeliveryLogger.emit(
      :superseded,
      event_type: job.arguments.first,
      customer_id: job.arguments.second.try(:id),
      lock_key: job.lock_key
    )
  end

  unique :until_and_while_executing, on_conflict: ON_CONFLICT, lock_ttl: 10.minutes

  EVENT_SERVICES = {
    EventDestinations::CustomerUsage::RefreshedService::EVENT_TYPE =>
      EventDestinations::CustomerUsage::RefreshedService
  }.freeze

  def perform(event_type, object)
    EVENT_SERVICES.fetch(event_type).call(object:)
  end
end
