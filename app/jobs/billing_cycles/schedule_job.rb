# frozen_string_literal: true

module BillingCycles
  class ScheduleJob < ApplicationJob
    # One in-flight schedule per customer: duplicate enqueues (a re-scan before this ran)
    # collapse instead of racing on the same customer. lock_ttl auto-expires the lock so a
    # crashed job never blocks that customer forever.
    unique :until_executed, on_conflict: :log, lock_ttl: 12.hours

    queue_as do
      if ActiveModel::Type::Boolean.new.cast(ENV["SIDEKIQ_BILLING"])
        :billing
      else
        :default
      end
    end

    def perform(customer_id)
      customer = Customer.find(customer_id)
      BillingCycles::ScheduleService.call!(customer:)
    end
  end
end
