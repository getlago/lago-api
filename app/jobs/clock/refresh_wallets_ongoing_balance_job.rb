# frozen_string_literal: true

module Clock
  class RefreshWalletsOngoingBalanceJob < ClockJob
    unique :until_executed, on_conflict: :log

    def perform
      return unless License.premium?

      Wallet.active.ready_to_be_refreshed.find_each do |wallet|
        Wallets::RefreshOngoingBalanceJob.perform_later(wallet)
      end
    end
  end
end
