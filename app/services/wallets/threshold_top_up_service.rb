# frozen_string_literal: true

module Wallets
  class ThresholdTopUpService < BaseService
    def initialize(wallet:)
      @wallet = wallet
      super
    end

    def call
      return if threshold_rule.nil?
      return if wallet.credits_ongoing_balance > threshold_rule.threshold_credits
      return if (pending_transactions_amount + wallet.credits_ongoing_balance) > threshold_rule.threshold_credits

      WalletTransactions::CreateJob.set(wait: 2.seconds).perform_later(
        organization_id: wallet.organization.id,
        params: {
          wallet_id: wallet.id,
          paid_credits:,
          granted_credits:,
          source: :threshold
        }
      )
    end

    private

    attr_reader :wallet

    def threshold_rule
      @threshold_rule ||= wallet.recurring_transaction_rules.where(trigger: :threshold).first
    end

    def pending_transactions_amount
      @pending_transactions_amount ||= wallet.wallet_transactions.pending.sum(:amount)
    end

    def paid_credits
      return (threshold_rule.target_ongoing_balance - wallet.credits_ongoing_balance).to_s if threshold_rule.target?

      threshold_rule.paid_credits.to_s
    end

    def granted_credits
      return "0.0" if threshold_rule.target?

      threshold_rule.granted_credits.to_s
    end
  end
end
