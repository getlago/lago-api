# frozen_string_literal: true

module Clock
  class SubscriptionsBillerJob < ApplicationJob
    include SentryCronConcern

    queue_as do
      if ActiveModel::Type::Boolean.new.cast(ENV['SIDEKIQ_CLOCK'])
        :clock
      else
        :default
      end
    end

    def perform
      Subscriptions::BillingService.call
    end
  end
end
