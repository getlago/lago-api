# frozen_string_literal: true

module Clock
  class TerminateEndedSubscriptionsJob < ApplicationJob
    include Sentry::Cron::MonitorCheckIns

    queue_as 'clock'

    if ENV['SENTRY_ENABLE_CRONS']
      sentry_monitor_check_ins slug: 'lago_terminate_ended_subscriptions', monitor_config: Sentry::Cron::MonitorConfig.from_crontab('5 */1 * * *')
    end

    def perform
      Subscription
        .joins(customer: :organization)
        .active
        .where(
          "DATE(subscriptions.ending_at#{Utils::Timezone.at_time_zone_sql}) = " \
          "DATE(?#{Utils::Timezone.at_time_zone_sql})",
          Time.current,
        )
        .find_each do |subscription|
          Subscriptions::TerminateService.call(subscription:)
        end
    end
  end
end
