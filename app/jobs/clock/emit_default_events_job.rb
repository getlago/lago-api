# frozen_string_literal: true

module Clock
  class EmitDefaultEventsJob < ClockJob
    def perform
      Organization.find_each do |organization|
        Subscriptions::OrganizationEmittingEventsJob.perform_later(organization:)
      end
    end
  end
end
