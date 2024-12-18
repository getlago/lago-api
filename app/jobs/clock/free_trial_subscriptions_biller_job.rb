# frozen_string_literal: true

module Clock
  class FreeTrialSubscriptionsBillerJob < ApplicationJob
    include SentryCronConcern

    queue_as do
      if ActiveModel::Type::Boolean.new.cast(ENV['SIDEKIQ_CLOCK'])
        :clock_worker
      else
        :clock
      end
    end

    def perform
      Subscriptions::FreeTrialBillingService.call
    end
  end
end
