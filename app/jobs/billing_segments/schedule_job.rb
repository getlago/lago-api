# frozen_string_literal: true

module BillingSegments
  # Legacy job name retained for queued jobs; process its customer directly.
  class ScheduleJob < BillingOperations::ProcessJob
  end
end
