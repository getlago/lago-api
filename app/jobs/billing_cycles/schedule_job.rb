# frozen_string_literal: true

module BillingCycles
  class ScheduleJob < ApplicationJob
    queue_as do
      if ActiveModel::Type::Boolean.new.cast(ENV["SIDEKIQ_BILLING"])
        :billing
      else
        :default
      end
    end

    def perform(subscription_product_item)
      BillingCycles::ScheduleService.call!(subscription_product_item:)
    end
  end
end
