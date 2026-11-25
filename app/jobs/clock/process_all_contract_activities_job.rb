# frozen_string_literal: true

module Clock
  class ProcessAllContractActivitiesJob < ClockJob
    unique :until_executed, on_conflict: :log

    def perform
      UsageMonitoring::ProcessAllContractActivitiesService.call! if License.premium?
    end
  end
end
