# frozen_string_literal: true

class Clock::ConsumeSubscriptionRefreshedQueueJob < ClockJob
  unique :until_executed, on_conflict: :log

  def perform(version = "v1")
    if version == "v1"
      Subscriptions::ConsumeSubscriptionRefreshedQueueService.call!
    else
      Subscriptions::ConsumeSubscriptionRefreshedQueueV2Service.call!
    end
  end
end
