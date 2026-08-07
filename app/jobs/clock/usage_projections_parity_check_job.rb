# frozen_string_literal: true

module Clock
  class UsageProjectionsParityCheckJob < ClockJob
    unique :until_executed, on_conflict: :log

    def perform
      UsageProjections::ParityCheckService.call
    end
  end
end
