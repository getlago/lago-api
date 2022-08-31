# frozen_string_literal: true

require 'clockwork'
require './config/boot'
require './config/environment'

module Clockwork
  handler do |job, time|
    puts "Running #{job} at #{time}"
  end

  error_handler do |error|
    Rails.logger.error(e.message)
    Rails.logger.error(e.backtrace.join("\n"))

    Sentry.capture_exception(error)
  end

  every(1.day, 'schedule:bill_customers', at: '01:00') do
    Clock::SubscriptionsBillerJob.perform_later
  end

  every(1.day, 'schedule:terminate_coupons', at: '5:00') do
    Clock::TerminateCouponsJob.perform_later
  end
end
