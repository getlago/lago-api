# frozen_string_literal: true

module Clock
  class WebhooksCleanupJob < ClockJob
    def perform
      Webhook.where("updated_at < ?", 90.days.ago).destroy_all
    end
  end
end
