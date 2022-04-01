# frozen_string_literal: true

module Clock
  class SubscriptionsBillerJob < ApplicationJob
    queue_as 'clock'

    def perform
      BillingService.new.call
    end
  end
end
