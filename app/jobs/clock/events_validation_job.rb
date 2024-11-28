# frozen_string_literal: true

module Clock
  class EventsValidationJob < ApplicationJob
    include SentryCronConcern

    queue_as 'clock'
    limits_concurrency to: 1, key: 'post_validate_events', duration: 1.hour

    def perform
      return if ActiveModel::Type::Boolean.new.cast(ENV['LAGO_DISABLE_EVENTS_VALIDATION'])

      # NOTE: refresh the last hour events materialized view
      Scenic.database.refresh_materialized_view(
        Events::LastHourMv.table_name,
        concurrently: false,
        cascade: false
      )

      organizations = Organization.where(
        id: Events::LastHourMv.pluck('DISTINCT(organization_id)')
      )

      organizations.find_each do |organization|
        next unless organization.webhook_endpoints.exists?

        Events::PostValidationJob.perform_later(organization:)
      end
    end
  end
end
