# frozen_string_literal: true

module Clock
  class TerminateEndedContractsJob < ClockJob
    unique :until_executed, on_conflict: :log

    def perform
      Contracts::TerminateAllEndedService.call!(timestamp: Time.current)
    end
  end
end
