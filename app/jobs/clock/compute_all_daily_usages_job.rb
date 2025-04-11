# frozen_string_literal: true

module Clock
  class ComputeAllDailyUsagesJob < ClockJob
    def perform
      DailyUsages::ComputeAllService.call(timestamp: Time.current)
    end
  end
end
