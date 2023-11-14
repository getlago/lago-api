# frozen_string_literal: true

module Clock
  class EventsValidationJob < ApplicationJob
    queue_as 'clock'

    def perform
      # NOTE: refresh the last hour events materialized view
      Scenic.database.refresh_materialized_view(
        Events::LastHourMv.table_name,
        concurrently: false,
        cascade: false,
      )

      organizations = Organization.where(
        id: Events::LastHourMv.pluck('DISTINCT(organization_id)'),
      )

      organizations.find_each do |organization|
        next unless organization.webhook_endpoints.exists?

        Events::PostValidationJob.perform_later(organization:)
      end
    end
  end
end
