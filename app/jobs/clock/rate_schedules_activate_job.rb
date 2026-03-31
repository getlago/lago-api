# frozen_string_literal: true

module Clock
  class RateSchedulesActivateJob < ClockJob
    unique :until_executed, on_conflict: :log

    def perform
      RateSchedules::ActivateService.call!
    end
  end
end