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

      job_params = {
        organization_id: wallet.organization.id,
        params: {
          wallet_id: wallet.id,
          paid_credits: paid_credits,
          granted_credits: granted_credits,
          source: :threshold,
          invoice_requires_successful_payment: threshold_rule.invoice_requires_successful_payment?
        }
      }
      job_params[:params][:metadata] = threshold_rule.metadata unless threshold_rule.metadata.empty?

      WalletTransactions::CreateJob.set(wait: 2.seconds).perform_later(job_params)
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
