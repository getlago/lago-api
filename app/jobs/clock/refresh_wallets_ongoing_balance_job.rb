# frozen_string_literal: true

module Clock
  class RefreshWalletsOngoingBalanceJob < ApplicationJob
    include Sentry::Cron::MonitorCheckIns

    queue_as 'clock'

    if ENV['SENTRY_ENABLE_CRONS']
      sentry_monitor_check_ins slug: 'lago_refresh_wallets_ongoing_balance', monitor_config: Sentry::Cron::MonitorConfig.from_crontab('*/5 * * * *')
    end

    def perform
      return unless License.premium?

      Wallet.active.find_each do |wallet|
        Wallets::RefreshOngoingBalanceJob.perform_later(wallet)
      end
    end
  end
end
