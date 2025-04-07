# frozen_string_literal: true

class Clock::ConsumeSubscriptionRefreshedQueueJob < ApplicationJob
  queue_as do
    if ActiveModel::Type::Boolean.new.cast(ENV["SIDEKIQ_CLOCK"])
      :clock_worker
    else
      :clock
    end
  end

  unique :until_executed, on_conflict: :log

  def perform
    Subscriptions::ConsumeSubscriptionRefreshedQueueService.call!
  end
end
