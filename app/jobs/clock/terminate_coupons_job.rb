# frozen_string_literal: true

module Clock
  class TerminateCouponsJob < ApplicationJob
    include Sentry::Cron::MonitorCheckIns

    queue_as 'clock'

    if ENV['SENTRY_ENABLE_CRONS']
      sentry_monitor_check_ins slug: 'lago_terminate_coupons', monitor_config: Sentry::Cron::MonitorConfig.from_crontab('30 */1 * * *')
    end

    def perform
      Coupons::TerminateService.new.terminate_all_expired
    end
  end
end
