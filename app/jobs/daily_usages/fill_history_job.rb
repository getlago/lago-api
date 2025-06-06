# frozen_string_literal: true

module DailyUsages
  class FillHistoryJob < ApplicationJob
    queue_as "long_running"

    def perform(subscription:, from_datetime:, sandbox: false)
      DailyUsages::FillHistoryService.call!(subscription:, from_datetime:, sandbox:)
    end
  end
end
