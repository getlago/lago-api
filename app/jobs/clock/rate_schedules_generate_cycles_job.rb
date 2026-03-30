# frozen_string_literal: true

module Clock
  class RateSchedulesGenerateCyclesJob < ClockJob
    def perform
      Organization.find_each do |organization|
        RateSchedules::GenerateAllCyclesJob.perform_later(organization)
      end
    end
  end
end
