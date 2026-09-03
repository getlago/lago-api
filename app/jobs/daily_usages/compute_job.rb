# frozen_string_literal: true

module DailyUsages
  class ComputeJob < ApplicationJob
    queue_as do
      if ActiveModel::Type::Boolean.new.cast(ENV["SIDEKIQ_ANALYTICS"])
        :analytics
      else
        :low_priority
      end
    end

    retry_on ActiveRecord::ActiveRecordError, wait: :polynomially_longer, attempts: 6
    unique :until_executing, on_conflict: :log, lock_ttl: 2.hours

    def perform(subscription, timestamp:)
      DailyUsages::ComputeService.call(subscription:, timestamp:).raise_if_error!
    end

    def lock_key_arguments
      subscription = arguments[0]
      timestamp = arguments[1][:timestamp]
      timestamp_in_customer_tz = timestamp.in_time_zone(subscription.customer.applicable_timezone)
      [subscription.id, timestamp_in_customer_tz.to_date]
    end
  end
end
