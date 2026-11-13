# frozen_string_literal: true

module Clock
  # Retained as a no-op so already-enqueued jobs remain compatible.
  class ScheduleBillingOperationsJob < ClockJob
    def perform
    end
  end
end
