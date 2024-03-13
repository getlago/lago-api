# frozen_string_literal: true

module Clock
  class SubscriptionsBillerJob < ApplicationJob
    include Sentry::Cron::MonitorCheckIns

    queue_as 'clock'

    if ENV['SENTRY_ENABLE_CRONS']
      sentry_monitor_check_ins slug: 'lago_bill_customers', monitor_config: Sentry::Cron::MonitorConfig.from_crontab('10 */1 * * *')
    end

    def perform
      Subscriptions::BillingService.call
    end
  end
end
