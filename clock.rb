# frozen_string_literal: true

require 'clockwork'
require './config/boot'
require './config/environment'

module Clockwork
  handler do |job, time|
    puts "Running #{job} at #{time}"
  end

  error_handler do |error|
    Rails.logger.error(error.message)
    Rails.logger.error(error.backtrace.join("\n"))

    Sentry.capture_exception(error)
  end

  # NOTE: All clocks run every hour to take customer timezones into account

  every(5.minutes, 'schedule:activate_subscriptions') do
    Clock::ActivateSubscriptionsJob
      .set(sentry: {"slug" => 'lago_activate_subscriptions', "cron" => '*/5 * * * *'})
      .perform_later
  end

  every(5.minutes, 'schedule:refresh_draft_invoices') do
    Clock::RefreshDraftInvoicesJob
      .set(sentry: {"slug" => 'lago_refresh_draft_invoices', "cron" => '*/5 * * * *'})
      .perform_later
  end

  lifetime_usage_refresh_interval = ENV["LAGO_LIFETIME_USAGE_REFRESH_INTERVAL_SECONDS"].presence || 5.minutes
  every(lifetime_usage_refresh_interval.to_i.seconds, 'schedule:refresh_lifetime_usages') do
    Clock::RefreshLifetimeUsagesJob
      .set(sentry: {"slug" => 'lago_refresh_lifetime_usages', "cron" => "#{lifetime_usage_refresh_interval} interval"})
      .perform_later
  end

  if ENV['LAGO_MEMCACHE_SERVERS'].present? || ENV['LAGO_REDIS_CACHE_URL'].present?
    every(5.minutes, 'schedule:refresh_wallets_ongoing_balance') do
      unless ENV['LAGO_DISABLE_WALLET_REFRESH'] == 'true'
        Clock::RefreshWalletsOngoingBalanceJob
          .set(sentry: {"slug" => 'lago_refresh_wallets_ongoing_balance', "cron" => '*/5 * * * *'})
          .perform_later
      end
    end
  end

  every(1.hour, 'schedule:terminate_ended_subscriptions', at: '*:05') do
    Clock::TerminateEndedSubscriptionsJob
      .set(sentry: {"slug" => 'lago_terminate_ended_subscriptions', "cron" => '5 */1 * * *'})
      .perform_later
  end

  every(1.hour, 'schedule:bill_customers', at: '*:10') do
    Clock::SubscriptionsBillerJob
      .set(sentry: {"slug" => 'lago_bill_customers', "cron" => '10 */1 * * *'})
      .perform_later
  end

  every(1.hour, 'schedule:finalize_invoices', at: '*:20') do
    Clock::FinalizeInvoicesJob
      .set(sentry: {"slug" => 'lago_finalize_invoices', "cron" => '20 */1 * * *'})
      .perform_later
  end

  every(1.hour, 'schedule:mark_invoices_as_payment_overdue', at: '*:25') do
    Clock::MarkInvoicesAsPaymentOverdueJob
      .set(sentry: {"slug" => 'lago_mark_invoices_as_payment_overdue', "cron" => '25 */1 * * *'})
      .perform_later
  end

  every(1.hour, 'schedule:terminate_coupons', at: '*:30') do
    Clock::TerminateCouponsJob
      .set(sentry: {"slug" => 'lago_terminate_coupons', "cron" => '30 */1 * * *'})
      .perform_later
  end

  every(1.hour, 'schedule:bill_ended_trial_subscriptions', at: '*:35') do
    Clock::FreeTrialSubscriptionsBillerJob
      .set(sentry: {"slug" => 'lago_bill_ended_trial_subscriptions', "cron" => '35 */1 * * *'})
      .perform_later
  end

  every(1.hour, 'schedule:terminate_wallets', at: '*:45') do
    Clock::TerminateWalletsJob
      .set(sentry: {"slug" => 'lago_terminate_wallets', "cron" => '45 */1 * * *'})
      .perform_later
  end

  every(1.hour, 'schedule:termination_alert', at: '*:50') do
    Clock::SubscriptionsToBeTerminatedJob
      .set(sentry: {"slug" => 'lago_termination_alert', "cron" => '50 */1 * * *'})
      .perform_later
  end

  every(1.hour, 'schedule:top_up_wallet_interval_credits', at: '*:55') do
    Clock::CreateIntervalWalletTransactionsJob
      .set(sentry: {"slug" => 'lago_top_up_wallet_interval_credits', "cron" => '55 */1 * * *'})
      .perform_later
  end

  every(1.day, 'schedule:clean_webhooks', at: '01:00') do
    Clock::WebhooksCleanupJob
      .set(sentry: {"slug" => 'lago_clean_webhooks', "cron" => '0 1 * * *'})
      .perform_later
  end

  unless ActiveModel::Type::Boolean.new.cast(ENV['LAGO_DISABLE_EVENTS_VALIDATION'])
    every(1.hour, 'schedule:post_validate_events', at: '*:05') do
      Clock::EventsValidationJob
        .set(sentry: {"slug" => 'lago_post_validate_events', "cron" => '5 */1 * * *'})
        .perform_later
    rescue => e
      Sentry.capture_exception(e)
    end
  end
end
