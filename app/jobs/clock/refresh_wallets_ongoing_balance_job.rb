# frozen_string_literal: true

module Clock
  class RefreshWalletsOngoingBalanceJob < ClockJob
    unique :until_executed, on_conflict: :log

    def perform
      return unless License.premium?

      Customer.with_active_wallets.where(wallets: {ready_to_be_refreshed: true}).find_each do |customer|
        Customers::RefreshWalletJob.perform_later(customer)
      end
    end
  end
end
