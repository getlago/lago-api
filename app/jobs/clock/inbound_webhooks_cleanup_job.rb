# frozen_string_literal: true

module Clock
  class InboundWebhooksCleanupJob < ClockJob
    def perform
      InboundWebhook.where("updated_at < ?", 90.days.ago).destroy_all
    end
  end
end
