# frozen_string_literal: true

module Clock
  class ComputeAllDailyUsagesJob < ClockJob
    unique :until_executed, on_conflict: :log

    queue_as do
      if ActiveModel::Type::Boolean.new.cast(ENV["SIDEKIQ_CLOCK"])
        :clock_worker
      elsif ActiveModel::Type::Boolean.new.cast(ENV["LAGO_REDIS_ANALYTICS_ENABLED"])
        :analytics
      else
        :clock
      end
    end

    def perform
      DailyUsages::ComputeAllService.call(timestamp: Time.current)
    end
  end
end
