# frozen_string_literal: true

module Clock
  class RateSchedulesBillerJob < ClockJob
    def perform
      Organization.find_each do |organization|
        RateSchedules::OrganizationBillingJob.perform_later(organization)
      end
    end
  end
end
