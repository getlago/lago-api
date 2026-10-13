# frozen_string_literal: true

module Clock
  class ActivateContractsJob < ClockJob
    unique :until_executed, on_conflict: :log

    def perform
      Contracts::ActivateAllPendingService.call!(timestamp: Time.current)
    end
  end
end
