# frozen_string_literal: true

module Clock
  class RealtimeUsageParityCheckJob < ClockJob
    unique :until_executed, on_conflict: :log

    def perform
      RealtimeUsage::ParityCheckService.call
    end
  end
end
