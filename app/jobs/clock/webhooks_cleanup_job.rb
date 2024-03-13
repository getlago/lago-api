# frozen_string_literal: true

module Clock
  class WebhooksCleanupJob < ApplicationJob
    include Sentry::Cron::MonitorCheckIns

    queue_as 'clock'

    if ENV['SENTRY_ENABLE_CRONS']
      sentry_monitor_check_ins slug: 'lago_clean_webhooks', monitor_config: Sentry::Cron::MonitorConfig.from_crontab('0 1 * * *')
    end

    def perform
      Webhook.where('updated_at < ?', 90.days.ago).destroy_all
    end
  end
end
