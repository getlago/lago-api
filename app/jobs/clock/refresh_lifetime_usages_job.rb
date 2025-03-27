# frozen_string_literal: true

module Clock
  class RefreshLifetimeUsagesJob < ApplicationJob
    if ENV["SENTRY_DSN"].present? && ENV["SENTRY_ENABLE_CRONS"].present?
      include SentryCronConcern
    end

    queue_as do
      if ActiveModel::Type::Boolean.new.cast(ENV["SIDEKIQ_CLOCK"])
        :clock_worker
      else
        :clock
      end
    end

    unique :until_executed, on_conflict: :log

    def perform
      return unless License.premium?

      LifetimeUsage.joins(:organization).merge(Organization.with_progressive_billing_support.or(Organization.with_lifetime_usage_support)).needs_recalculation.find_each do |ltu|
        LifetimeUsages::RecalculateAndCheckJob.perform_later(ltu)
      end
    end
  end
end
