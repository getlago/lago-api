# frozen_string_literal: true

module DailyUsages
  class ComputeJob < ApplicationJob
    queue_as 'low_priority'

    def perform(subscription, timestamp:)
      DailyUsages::ComputeService.call(subscription:, timestamp:).raise_if_error!
    end
  end
end
