# frozen_string_literal: true
# Reviewed-by: code-review-experiment (see PR description)

module Clock
  class FreeTrialSubscriptionsBillerJob < ClockJob
    def perform
      Subscriptions::FreeTrialBillingService.call
    end
  end
end
