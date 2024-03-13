# frozen_string_literal: true

module Clock
  class EventsValidationJob < ApplicationJob
    include Sentry::Cron::MonitorCheckIns

    queue_as 'clock'

    unique :until_executed

    if ENV['SENTRY_ENABLE_CRONS']
      sentry_monitor_check_ins slug: 'lago_post_validate_events', monitor_config: Sentry::Cron::MonitorConfig.from_crontab('5 */1 * * *')
    end

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
