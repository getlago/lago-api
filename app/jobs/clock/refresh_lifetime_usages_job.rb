# frozen_string_literal: true

module Clock
  class RefreshLifetimeUsagesJob < ApplicationJob
    include SentryCronConcern

    queue_as 'clock'
    unique :until_executed, on_conflict: :log

    def perform
      return unless License.premium?

      LifetimeUsage.joins(:organization).merge(Organization.with_progressive_billing_support).needs_recalculation.find_each do |ltu|
        LifetimeUsages::RecalculateAndCheckJob.perform_later(ltu)
      end
    end
  end
end
