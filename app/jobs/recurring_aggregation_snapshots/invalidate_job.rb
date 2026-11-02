# frozen_string_literal: true

module RecurringAggregationSnapshots
  class InvalidateJob < ApplicationJob
    queue_as "low_priority"

    def perform(subscription, codes)
      RecurringAggregationSnapshots::InvalidateService.call!(subscription:, codes:)
    end
  end
end
