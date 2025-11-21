# frozen_string_literal: true

module WalletScenarioHelper
  include CommonScenarioHelper

  def create_wallet(params, as: :json, **kwargs)
    api_call(**kwargs) do
      post_with_token(organization, "/api/v1/wallets", {wallet: params})
    end
    parse_result(as, Wallet, :wallet)
  end

  def create_wallet_transaction(params, as: :json, **kwargs)
    api_call(**kwargs) do
      post_with_token(organization, "/api/v1/wallet_transactions", {wallet_transaction: params})
    end
    parse_result(as, WalletTransaction, :wallet_transactions)
  end

  def recalculate_wallet_balances
    Clock::RefreshLifetimeUsagesJob.perform_later
    Clock::RefreshWalletsOngoingBalanceJob.perform_later
    perform_all_enqueued_jobs
  end
end
