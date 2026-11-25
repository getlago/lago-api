# frozen_string_literal: true

module Clock
  class ProcessAllContractActivitiesJob < ClockJob
    unique :until_executed, on_conflict: :log

    def perform
      return unless License.premium?

      UsageMonitoring::ProcessAllContractActivitiesService.call!
    end
  end
end
