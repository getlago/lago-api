# frozen_string_literal: true

module Clock
  class RefreshLifetimeUsagesJob < ClockJob
    unique :until_executed, on_conflict: :log

    def perform
      return unless License.premium?

      LifetimeUsage.joins(:organization).merge(Organization.with_progressive_billing_support.or(Organization.with_lifetime_usage_support)).needs_recalculation.find_each do |ltu|
        LifetimeUsages::RecalculateAndCheckJob.perform_later(ltu)
      end
    end
  end
end
