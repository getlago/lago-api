# frozen_string_literal: true

module Clock
  class TerminateWalletsJob < ClockJob
    unique :until_executed, on_conflict: :log, lock_ttl: 4.hours

    def perform
      Wallet.active.expired.find_each do |wallet|
        if wallet.invoice_usage_on_expiration?
          Wallets::ExpireJob.perform_later(wallet)
        else
          Wallets::TerminateService.call(wallet:)
        end
      end
    end
  end
end
