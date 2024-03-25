# frozen_string_literal: true

module Clock
  class RefreshWalletsOngoingBalanceJob < ApplicationJob
    include SentryConcern

    queue_as 'clock'

    def perform
      return unless License.premium?

      Wallet.active.find_each do |wallet|
        Wallets::RefreshOngoingBalanceJob.perform_later(wallet)
      end
    end
  end
end
