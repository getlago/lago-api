# frozen_string_literal: true

module Clock
  class RefreshWalletsOngoingBalanceJob < ApplicationJob
    queue_as 'clock'

    unique :until_executed

    def perform
      return unless License.premium?

      Wallet.active.find_each do |wallet|
        Wallets::RefreshOngoingBalanceJob.perform_later(wallet)
      end
    end
  end
end
