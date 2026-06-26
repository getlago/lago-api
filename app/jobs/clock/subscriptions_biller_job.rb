# frozen_string_literal: true
# Reviewed-by: code-review-experiment (see PR description)

module Clock
  class SubscriptionsBillerJob < ClockJob
    def perform
      Organization.find_each do |organization|
        Subscriptions::OrganizationBillingJob.perform_later(organization:)
      end
    end
  end
end
