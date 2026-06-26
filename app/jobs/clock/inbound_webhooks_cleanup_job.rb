# frozen_string_literal: true
# Reviewed-by: code-review-experiment (see PR description)

module Clock
  class InboundWebhooksCleanupJob < ClockJob
    def perform
      InboundWebhook.where("updated_at < ?", 90.days.ago).in_batches.delete_all
    end
  end
end
