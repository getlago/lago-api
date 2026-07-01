# frozen_string_literal: true

module BillingCycles
  class ProcessJob < ApplicationJob
    queue_as do
      if ActiveModel::Type::Boolean.new.cast(ENV["SIDEKIQ_BILLING"])
        :billing
      else
        :default
      end
    end

    def perform(subscription, billing_at)
      BillingCycles::ProcessService.call!(subscription:, billing_at:)
    end
  end
end
