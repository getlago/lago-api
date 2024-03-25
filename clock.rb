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
    Clock::ActivateSubscriptionsJob.perform_later(
        :slug => "activate_subscriptions", :cron => "*/5 * * * *"
    )
  end

  every(5.minutes, 'schedule:refresh_draft_invoices') do
    Clock::RefreshDraftInvoicesJob.perform_later(
      :slug => "lago_refresh_draft_invoices", :cron => "*/5 * * * *"
    )
  end

  every(5.minutes, 'schedule:refresh_wallets_ongoing_balance') do
    Clock::RefreshWalletsOngoingBalanceJob.perform_later(
      :slug => "lago_refresh_wallets_ongoing_balance", :cron => "*/5 * * * *"
    )
  end

  every(1.hour, 'schedule:terminate_ended_subscriptions', at: '*:05') do
    Clock::TerminateEndedSubscriptionsJob.perform_later(
      :slug => "lago_terminate_ended_subscriptions", :cron => "5 */1 * * *"
    )
  end

  every(1.hour, 'schedule:bill_customers', at: '*:10') do
    Clock::SubscriptionsBillerJob.perform_later(
      :slug => "lago_bill_customers", :cron => "10 */1 * * *"
    )
  end

  every(1.hour, 'schedule:finalize_invoices', at: '*:20') do
    Clock::FinalizeInvoicesJob.perform_later(
      :slug => "lago_finalize_invoices", :cron => "20 */1 * * *"
    )
  end

  every(1.hour, 'schedule:terminate_coupons', at: '*:30') do
    Clock::TerminateCouponsJob.perform_later(
      :slug => "lago_terminate_coupons", :cron => "30 */1 * * *"
    )
  end

  every(1.hour, 'schedule:terminate_wallets', at: '*:45') do
    Clock::TerminateWalletsJob.perform_later(
      :slug => "lago_terminate_wallets", :cron => "45 */1 * * *"
    )
  end

  every(1.hour, 'schedule:termination_alert', at: '*:50') do
    Clock::SubscriptionsToBeTerminatedJob.perform_later(
      :slug => "lago_termination_alert", :cron => "50 */1 * * *"
    )
  end

  every(1.hour, 'schedule:top_up_wallet_interval_credits', at: '*:55') do
    Clock::CreateIntervalWalletTransactionsJob.perform_later(
      :slug => "lago_top_up_wallet_interval_credits", :cron => "55 */1 * * *"
    )
  end

  every(1.day, 'schedule:clean_webhooks', at: '01:00') do
    Clock::WebhooksCleanupJob.perform_later(
      :slug => "lago_clean_webhooks", :cron => "0 1 * * *"
    )
  end

  every(1.hour, 'schedule:post_validate_events', at: '*:05') do
    Clock::EventsValidationJob.perform_later(
      :slug => "lago_post_validate_events", :cron => "5 */1 * * *"
    )
  rescue StandardError => e
    Sentry.capture_exception(e)
  end
end
