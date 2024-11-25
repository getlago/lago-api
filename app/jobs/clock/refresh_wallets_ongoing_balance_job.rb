# frozen_string_literal: true

module Clock
  class RefreshWalletsOngoingBalanceJob < ApplicationJob
    include SentryCronConcern

    queue_as 'clock'
    limits_concurrency to: 1, key: 'refresh_wallets_ongoing_balance', duration: 5.minutes

    def perform
      return unless License.premium?

      Wallet.active.ready_to_be_refreshed.find_each do |wallet|
        Wallets::RefreshOngoingBalanceJob.perform_later(wallet)
      end
    end
  end
end
