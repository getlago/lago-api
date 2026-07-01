# frozen_string_literal: true

module Clock
  class SubscriptionsBillerJob < ClockJob
    unique :until_executed, on_conflict: :log

    def perform
      Organization.find_each do |organization|
        Subscriptions::OrganizationBillingJob.perform_later(organization:)
      end
    end
  end
end
