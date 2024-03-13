# frozen_string_literal: true

module Clock
  class TerminateWalletsJob < ApplicationJob
    include Sentry::Cron::MonitorCheckIns

    queue_as 'clock'

    if ENV['SENTRY_ENABLE_CRONS']
      sentry_monitor_check_ins slug: 'lago_terminate_wallets', monitor_config: Sentry::Cron::MonitorConfig.from_crontab('45 */1 * * *')
    end

    def perform
      Wallet.active.expired.find_each do |wallet|
        Wallets::TerminateService.call(wallet:)
      end
    end
  end
end
