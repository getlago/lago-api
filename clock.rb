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

  every(5.minutes, 'schedule:activate_subscriptions') do
    Clock::ActivateSubscriptionsJob.perform_later(:sentry => {
      :slug => "activate_subscriptions", :cron => "*/5 * * * *"
    })
  end

  every(5.minutes, 'schedule:refresh_draft_invoices') do
    # NOTE: Sentry Cron monitor within activejob will need time updated if clock time changed here
    Clock::RefreshDraftInvoicesJob.perform_later
  end

  every(5.minutes, 'schedule:refresh_wallets_ongoing_balance') do
    # NOTE: Sentry Cron monitor within activejob will need time updated if clock time changed here
    Clock::RefreshWalletsOngoingBalanceJob.perform_later
  end

  every(1.hour, 'schedule:terminate_ended_subscriptions', at: '*:05') do
    # NOTE: Sentry Cron monitor within activejob will need time updated if clock time changed here
    Clock::TerminateEndedSubscriptionsJob.perform_later
  end

  every(1.hour, 'schedule:bill_customers', at: '*:10') do
    # NOTE: Sentry Cron monitor within activejob will need time updated if clock time changed here
    Clock::SubscriptionsBillerJob.perform_later
  end

  every(1.hour, 'schedule:finalize_invoices', at: '*:20') do
    # NOTE: Sentry Cron monitor within activejob will need time updated if clock time changed here
    Clock::FinalizeInvoicesJob.perform_later
  end

  every(1.hour, 'schedule:terminate_coupons', at: '*:30') do
    # NOTE: Sentry Cron monitor within activejob will need time updated if clock time changed here
    Clock::TerminateCouponsJob.perform_later
  end

  every(1.hour, 'schedule:terminate_wallets', at: '*:45') do
    # NOTE: Sentry Cron monitor within activejob will need time updated if clock time changed here
    Clock::TerminateWalletsJob.perform_later
  end

  every(1.hour, 'schedule:termination_alert', at: '*:50') do
    # NOTE: Sentry Cron monitor within activejob will need time updated if clock time changed here
    Clock::SubscriptionsToBeTerminatedJob.perform_later
  end

  every(1.hour, 'schedule:top_up_wallet_interval_credits', at: '*:55') do
    # NOTE: Sentry Cron monitor within activejob will need time updated if clock time changed here
    Clock::CreateIntervalWalletTransactionsJob.perform_later
  end

  every(1.day, 'schedule:clean_webhooks', at: '01:00') do
    # NOTE: Sentry Cron monitor within activejob will need time updated if clock time changed here
    Clock::WebhooksCleanupJob.perform_later
  end

  every(1.hour, 'schedule:post_validate_events', at: '*:05') do
    # NOTE: Sentry Cron monitor within activejob will need time updated if clock time changed here
    Clock::EventsValidationJob.perform_later
  end
end
