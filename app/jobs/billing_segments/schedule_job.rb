# frozen_string_literal: true

module BillingSegments
  class ScheduleJob < ApplicationJob
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
      BillingSegments::ScheduleService.call!(customer:)
    end
  end
end
