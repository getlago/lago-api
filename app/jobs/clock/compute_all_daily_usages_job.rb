# frozen_string_literal: true

module Clock
  class ComputeAllDailyUsagesJob < ApplicationJob
    if ENV["SENTRY_DSN"].present? && ENV["SENTRY_ENABLE_CRONS"].present?
      include SentryCronConcern
    end

    queue_as do
      if ActiveModel::Type::Boolean.new.cast(ENV["SIDEKIQ_CLOCK"])
        :clock_worker
      else
        :clock
      end
    end

    def perform
      DailyUsages::ComputeAllService.call(timestamp: Time.current)
    end
  end
end
