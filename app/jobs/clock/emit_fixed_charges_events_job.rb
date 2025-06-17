# frozen_string_literal: true

module Clock
  class EmitFixedChargesEventsJob < ClockJob
    def perform
      Organization.find_each do |organization|
        Subscriptions::OrganizationEventsEmittingJob.perform_later(organization:)
      end
    end
  end
end
