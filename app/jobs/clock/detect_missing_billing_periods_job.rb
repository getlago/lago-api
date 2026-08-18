# frozen_string_literal: true

module Clock
  class DetectMissingBillingPeriodsJob < ClockJob
    unique :until_executed, on_conflict: :log, lock_ttl: 30.minutes

    def perform
      Organization.find_each do |organization|
        Subscriptions::BillingPeriods::DetectMissingService.call!(organization:)
      end
    end
  end
end
