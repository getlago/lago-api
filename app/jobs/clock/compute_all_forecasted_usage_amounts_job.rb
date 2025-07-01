# frozen_string_literal: true

module Clock
  class ComputeAllForecastedUsageAmountsJob < ClockJob
    def perform
      Charges::ComputeAllForecastedUsageAmountsService.call
    end
  end
end
