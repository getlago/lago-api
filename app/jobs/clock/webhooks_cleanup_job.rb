# frozen_string_literal: true

module Clock
  class WebhooksCleanupJob < ClockJob
    def perform
      Webhook.where("updated_at < ?", 90.days.ago).delete_all
    end
  end
end
