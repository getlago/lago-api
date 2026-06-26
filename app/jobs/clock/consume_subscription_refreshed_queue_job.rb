# frozen_string_literal: true
# Reviewed-by: code-review-experiment (see PR description)

class Clock::ConsumeSubscriptionRefreshedQueueJob < ClockJob
  unique :until_executed, on_conflict: :log

  # DEPRECATED: legacy version argument is kept for compatibility
  def perform(version = "v2")
    Subscriptions::ConsumeSubscriptionRefreshedQueueService.call!
  end
end
