# frozen_string_literal: true

module Clock
  class ActivateSubscriptionsJob < ApplicationJob
    include Sentry::Cron::MonitorCheckIns

    queue_as 'clock'

    unique :until_executed, on_conflict: :log

    if ENV['SENTRY_ENABLE_CRONS']
      sentry_monitor_check_ins slug: 'lago_activate_subscriptions_job', monitor_config: Sentry::Cron::MonitorConfig.from_crontab('*/5 * * * *')
    end

    def perform
      Subscriptions::ActivateService.new(timestamp: Time.current.to_i).activate_all_pending
    end
  end
end
