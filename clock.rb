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

  # NOTE: All clocks run every hour to take customer timezones into account

  every(1.hour, 'schedule:activate_subscriptions', at: '**:30') do
    Clock::ActivateSubscriptionsJob.perform_later
  end

  every(1.hour, 'schedule:bill_customers', at: '*:10') do
    Clock::SubscriptionsBillerJob.perform_later
  end

  every(1.hour, 'schedule:finalize_invoices', at: '*:20') do
    Clock::FinalizeInvoicesJob.perform_later
  end

  every(1.hour, 'schedule:terminate_coupons', at: '*:30') do
    Clock::TerminateCouponsJob.perform_later
  end

  every(1.hour, 'schedule:terminate_wallets', at: '*:45') do
    Clock::TerminateWalletsJob.perform_later
  end
end
