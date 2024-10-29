# frozen_string_literal: true

module Clock
  class ComputeAllDailyUsagesJob < ApplicationJob
    include SentryCronConcern

    queue_as 'clock'

    def perform
      DailyUsages::ComputeAllService.call
    end
  end
end
