# frozen_string_literal: true

module Clock
  class SubscriptionsBillerJob < ApplicationJob
    include SentryConcern

    queue_as 'clock'

    def perform
      Subscriptions::BillingService.call
    end
  end
end
