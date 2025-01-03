# frozen_string_literal: true

module Clock
  class InboundWebhooksCleanupJob < ApplicationJob
    include SentryCronConcern

    queue_as "clock"

    def perform
      InboundWebhook.where("updated_at < ?", 90.days.ago).destroy_all
    end
  end
end
