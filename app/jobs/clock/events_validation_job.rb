# frozen_string_literal: true

module Clock
  class EventsValidationJob < ApplicationJob
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

    unique :until_executed

    def perform
      # NOTE: refresh the last hour events materialized view
      Scenic.database.refresh_materialized_view(
        Events::LastHourMv.table_name,
        concurrently: false,
        cascade: false
      )

      organizations = Organization.where(
        id: Events::LastHourMv.pluck("DISTINCT(organization_id)")
      )

      organizations.find_each do |organization|
        next unless organization.webhook_endpoints.exists?

        Events::PostValidationJob.perform_later(organization:)
      end
    end
  end
end
