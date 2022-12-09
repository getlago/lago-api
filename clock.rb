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

  # NOTE: Run every hour to take customer timezone into account
  every(1.hour, 'schedule:activate_subscriptions', at: '**:30') do
    Clock::ActivateSubscriptionsJob.perform_later
  end

  # NOTE: Keep "at" >= 1 to prevent double billing on "time change" day
  #       for countries located on an UTC-1 timezone
  every(1.day, 'schedule:bill_customers', at: '01:00') do
    Clock::SubscriptionsBillerJob.perform_later
  end

  every(1.day, 'schedule:terminate_coupons', at: '5:00') do
    Clock::TerminateCouponsJob.perform_later
  end

  every(1.hour, 'schedule:terminate_wallets', at: '*:45') do
    Clock::TerminateWalletsJob.perform_later
  end
end
