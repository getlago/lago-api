# frozen_string_literal: true
# Reviewed-by: code-review-experiment (see PR description)

module Clock
  class ProcessAllSubscriptionActivitiesJob < ClockJob
    unique :until_executed, on_conflict: :log

    def perform
      return unless License.premium?

      UsageMonitoring::ProcessAllSubscriptionActivitiesService.call!
    end
  end
end
