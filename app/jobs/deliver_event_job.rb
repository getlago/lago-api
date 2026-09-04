# frozen_string_literal: true

class DeliverEventJob < ApplicationJob
  # POC only: a dedicated queue is a post-POC decision.
  queue_as :default

  # Snapshot payloads carry a read-time `version`, which only orders correctly if no two
  # jobs read the usage cache for one customer at once: the per-charge fragments interleave
  # and a later version can then carry staler content.
  unique :until_and_while_executing, on_conflict: :log, lock_ttl: 10.minutes

  EVENT_SERVICES = {
    "customer_usage.refreshed" => EventDestinations::CustomerUsage::RefreshedService
  }.freeze

  def perform(event_type, object)
    EVENT_SERVICES.fetch(event_type).call(object:)
  end
end
