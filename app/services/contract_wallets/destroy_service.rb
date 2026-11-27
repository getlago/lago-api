# frozen_string_literal: true

module ContractWallets
  class DestroyService < BaseService
    Result = BaseResult[:contract_wallet]

    activity_loggable(
      action: "contract_wallet.deleted",
      record: -> { contract_wallet }
    )

    def initialize(contract_wallet:)
      @contract_wallet = contract_wallet
      super
    end

    def call
      return result.not_found_failure!(resource: "contract_wallet") unless contract_wallet

      # Locked so the status check holds: the clock may end the contract meanwhile.
      # Unlike FOR UPDATE, it lets rows that reference the contract be inserted meanwhile.
      contract.with_lock("FOR NO KEY UPDATE") do
        return result.forbidden_failure!(code: "contract_not_live") unless Contract::LIVE_STATUSES.include?(contract.status)

        # Settling an entry moves the wallet's balance, so it waits for this lock.
        contract_wallet.lock!
        return result.not_found_failure!(resource: "contract_wallet") if contract_wallet.discarded?

        return result.forbidden_failure!(code: "wallet_holds_credit") if holds_credit?

        if contract_wallet.credit_allocations.exists?
          return result.forbidden_failure!(code: "wallet_has_credit_allocations")
        end

        UsageMonitoring::CatalogWalletAlerts::DeleteAllService.call!(catalog_wallets: contract_wallet)
        # The taxes, scope and metadata stay on the deleted wallet, which still renders them.
        contract_wallet.discard!
      end

      result.contract_wallet = contract_wallet
      result
    end

    private

    attr_reader :contract_wallet

    delegate :contract, to: :contract_wallet

    # Credit it can spend, or credit bought that is not settled yet: a late payment still settles a failed purchase.
    def holds_credit?
      contract_wallet.balance_cents.positive? || contract_wallet.transactions.inbound.not_settled.exists?
    end
  end
end
