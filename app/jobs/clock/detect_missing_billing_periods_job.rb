# frozen_string_literal: true

module Clock
  class DetectMissingBillingPeriodsJob < ClockJob
    unique :until_executed, on_conflict: :log, lock_ttl: 30.minutes

    def perform
      # Isolated per organization: the sweep only reports and heals, so one organization failing
      # must not take the report of every organization after it with it.
      Organization.find_each do |organization|
        Subscriptions::BillingPeriods::DetectMissingService.call!(organization:)
      rescue => e
        Sentry.capture_exception(e, extra: {organization_id: organization.id})
      end
    end
  end
end
