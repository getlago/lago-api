# frozen_string_literal: true

module Clock
  class TerminateWalletsJob < ClockJob
    unique :until_executed, on_conflict: :log, lock_ttl: 4.hours

    def perform
      Wallet.active.expired.includes(:organization).find_each do |wallet|
        if wallet.expiration_invoicing_enabled?
          Wallets::ExpireJob.perform_later(wallet)
        else
          Wallets::TerminateService.call(wallet:)
        end
      end
    end
  end
end
