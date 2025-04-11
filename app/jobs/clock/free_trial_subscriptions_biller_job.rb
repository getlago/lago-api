# frozen_string_literal: true

module Clock
  class FreeTrialSubscriptionsBillerJob < ClockJob
    def perform
      Subscriptions::FreeTrialBillingService.call
    end
  end
end
