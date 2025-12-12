# frozen_string_literal: true

module Clock
  class RefreshWalletsOngoingBalanceJob < ClockJob
    unique :until_executed, on_conflict: :log

    def perform
      return unless License.premium?

      Customer.with_active_wallets.awaiting_wallet_refresh.find_each do |customer|
        Customers::RefreshWalletJob.perform_later(customer)
      end
    end
  end
end
