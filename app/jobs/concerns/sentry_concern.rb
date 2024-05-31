# frozen_string_literal: true

module SentryConcern
  include Sentry::Cron::MonitorCheckIns

  def perform(sentry = {})
    # Super perform the actual job
    super
    # Then if sentry crons are enabled, check in
    if ENV['SENTRY_ENABLE_CRONS']
      sentry_monitor_check_ins(
        slug: sentry[:slug],
        monitor_config: Sentry::Cron::MonitorConfig.from_crontab(sentry[:cron])
      )
    end
  end
end
