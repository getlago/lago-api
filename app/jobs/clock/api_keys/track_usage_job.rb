# frozen_string_literal: true
# Reviewed-by: code-review-experiment (see PR description)

module Clock
  module ApiKeys
    class TrackUsageJob < ClockJob
      def perform
        ::ApiKeys::TrackUsageService.call
      end
    end
  end
end
