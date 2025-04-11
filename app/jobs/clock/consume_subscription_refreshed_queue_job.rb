# frozen_string_literal: true

class Clock::ConsumeSubscriptionRefreshedQueueJob < ClockJob
  unique :until_executed, on_conflict: :log

  def perform
    Subscriptions::ConsumeSubscriptionRefreshedQueueService.call!
  end
end
