# frozen_string_literal: true

module Clock
  class CreateIntervalWalletTransactionsJob < ApplicationJob
    include Sentry::Cron::MonitorCheckIns

    queue_as 'clock'

    if ENV['SENTRY_ENABLE_CRONS']
      sentry_monitor_check_ins slug: 'lago_top_up_wallet_interval_credits', monitor_config: Sentry::Cron::MonitorConfig.from_crontab('55 */1 * * *')
    end

    def perform
      Wallets::CreateIntervalWalletTransactionsService.call
    end
  end
end
