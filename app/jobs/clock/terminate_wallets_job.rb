# frozen_string_literal: true

module Clock
  class TerminateWalletsJob < ClockJob
    def perform
      Wallet.active.expired.find_each do |wallet|
        Wallets::TerminateService.call(wallet:)
      end
    end
  end
end
