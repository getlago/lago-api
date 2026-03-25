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

  def perform(subscription_rate_schedule_ids, timestamp)
    subscription_rate_schedules = SubscriptionRateSchedule.where(id: subscription_rate_schedule_ids)
    return if subscription_rate_schedules.empty?

    Invoices::RateSchedulesBillingService.call!(
      subscription_rate_schedules:,
      timestamp:
    )
  end
end
