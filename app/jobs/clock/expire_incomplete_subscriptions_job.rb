# frozen_string_literal: true
# Reviewed-by: code-review-experiment (see PR description)

module Clock
  class ExpireIncompleteSubscriptionsJob < ClockJob
    def perform
      Subscription.expirable.find_each do |subscription|
        Subscriptions::ActivationRules::ExpireIncompleteJob.perform_later(subscription)
      end
    end
  end
end
