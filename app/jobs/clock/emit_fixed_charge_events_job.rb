# frozen_string_literal: true

module Clock
  class EmitFixedChargeEventsJob < ClockJob
    unique :until_executed, on_conflict: :log

    def perform
      Organization.find_each do |organization|
        Subscriptions::OrganizationEmitFixedChargeEventsJob.perform_later(organization:, timestamp: Time.current.to_i)
      end
    end
  end
end
