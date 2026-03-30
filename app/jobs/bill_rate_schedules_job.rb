# frozen_string_literal: true

class BillRateSchedulesJob < ApplicationJob
  queue_as do
    if ActiveModel::Type::Boolean.new.cast(ENV["SIDEKIQ_BILLING"])
      :billing
    else
      :default
    end
  end

  unique :until_executed, on_conflict: :log, lock_ttl: 12.hours

  retry_on Customers::FailedToAcquireLock, ActiveRecord::StaleObjectError, attempts: MAX_LOCK_RETRY_ATTEMPTS, wait: random_lock_retry_delay
  retry_on Sequenced::SequenceError, ActiveJob::DeserializationError, wait: :polynomially_longer, attempts: 15, jitter: 0.75

  def perform(subscription_rate_schedule_ids, timestamp)
    billing_date = Time.zone.at(timestamp).to_date

    # Re-validate billability for idempotency on job retries.
    # After a successful billing, intervals_billed advances and next_billing_date
    # moves forward — the SRS won't match these conditions on retry.
    subscription_rate_schedules = SubscriptionRateSchedule
      .where(id: subscription_rate_schedule_ids)
      .where(next_billing_date: ..billing_date)
      .where("intervals_to_bill IS NULL OR intervals_billed < intervals_to_bill")
      .includes(:subscription, :rate_schedule, :product_item)
    return if subscription_rate_schedules.empty?

    Invoices::RateSchedulesBillingService.call!(
      subscription_rate_schedules:,
      timestamp:
    )
  end

  def lock_key_arguments
    arguments = self.arguments.dup

    return arguments if arguments[0].empty?

    subscription_rate_schedules = SubscriptionRateSchedule.where(id: arguments[0]).includes(:subscription)
    return arguments if subscription_rate_schedules.empty?

    customer = subscription_rate_schedules.first.subscription.customer
    date = Time.zone.at(arguments[1]).in_time_zone(customer.applicable_timezone).to_date
    arguments[1] = date
    arguments
  end
end
