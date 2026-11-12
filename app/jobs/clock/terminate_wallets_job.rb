# frozen_string_literal: true

module Clock
  class TerminateWalletsJob < ClockJob
    unique :until_executed, on_conflict: :log, lock_ttl: 4.hours

    def perform
      Wallet.active.expired.includes(:organization).find_each do |wallet|
        # Disabling the invoicing must not terminate a wallet that an unsettled expiration invoice still spends.
        if wallet.invoice_usage_on_expiration? || wallet.reserved_for_expiration_invoice?
          Wallets::ExpireWithInvoicingJob.perform_later(wallet)
        else
          Wallets::TerminateService.call(wallet:)
        end
      end
    end
  end
end
