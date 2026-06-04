# frozen_string_literal: true

require "clockwork"
require "./config/boot"
require "./config/environment"

module Clockwork
  handler do |job, time|
    puts "Running #{job} at #{time}" # rubocop:disable Rails/Output
  end

  error_handler do |error|
    Rails.logger.error(error.message)
    Rails.logger.error(error.backtrace.join("\n"))

    Sentry.capture_exception(error)
  end

  # NOTE: All clocks run every hour to take customer timezones into account

  if ActiveModel::Type::Bolean.new.cast(ENV["LAGO_REDIS_ANALYTICS_ENABLED"])
    every(1.hour, "schedule:compute_daily_usage", at: "*:15") do
      Clock::ComputeAllDailyUsagesJob
        .set(sentry: {"slug" => "lago_compute_daily_usage", "cron" => "15 */1 * * *"})
        .perform_later
    end
  end
end
