# frozen_string_literal: true

module Clock
  class RefreshLifetimUsageJob < ApplicationJob
    include SentryCronConcern

    queue_as 'clock'
    unique :until_executed, on_conflict: :log

    def perform
      LifetimeUsage.where(recalculate_current_usage: true).or(recalculate_invoiced_usage: true).find_each do |ltu|
        LifetimeUsages::RefreshJob.perform_later(ltu)
      end
    end
  end
end
