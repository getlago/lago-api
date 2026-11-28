# frozen_string_literal: true

module Clock
  class ConsumeContractRefreshedQueueJob < ClockJob
    unique :until_executed, on_conflict: :log

    def perform
      Contracts::ConsumeRefreshedQueueService.call!
    end
  end
end
