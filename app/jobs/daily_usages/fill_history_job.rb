# frozen_string_literal: true

module DailyUsages
  class FillHistoryJob < ApplicationJob
    queue_as "long_running"

    def perform(subscription:, from_datetime:)
      DailyUsages::FillHistoryService.call!(subscription:, from_datetime:)
    end
  end
end
