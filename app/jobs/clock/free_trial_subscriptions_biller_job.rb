# frozen_string_literal: true

module Clock
  class FreeTrialSubscriptionsBillerJob < ApplicationJob
    queue_as 'clock'

    def perform
      Subscriptions::FreeTrialBillingService.call
    end
  end
end
