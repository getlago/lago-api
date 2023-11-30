# frozen_string_literal: true

module Wallets
  module Balance
    class DecreaseService < BaseService
      def initialize(wallet:, credits_amount:)
        super(nil)

        @wallet = wallet
        @credits_amount = credits_amount
      end

      def call
        currency = wallet.balance.currency
        amount_cents = wallet.rate_amount * credits_amount * currency.subunit_to_unit

        wallet.update!(
          balance_cents: wallet.balance_cents - amount_cents,
          credits_balance: wallet.credits_balance - credits_amount,
          last_balance_sync_at: Time.zone.now,
          consumed_credits: wallet.consumed_credits + credits_amount,
          consumed_amount_cents: wallet.consumed_amount_cents + amount_cents,
          last_consumed_credit_at: Time.current,
        )

        handle_threshold_top_up

        result.wallet = wallet
        result
      end

      private

      attr_reader :wallet, :credits_amount

      def handle_threshold_top_up
        threshold_rule = wallet.recurring_transaction_rules.where(rule_type: :threshold).first

        return if threshold_rule.nil? || wallet.credits_balance > threshold_rule.threshold_credits

        WalletTransactions::CreateJob.set(wait: 2.seconds).perform_later(
          organization_id: wallet.organization.id,
          wallet_id: wallet.id,
          paid_credits: threshold_rule.paid_credits.to_s,
          granted_credits: threshold_rule.granted_credits.to_s,
          source: :threshold,
        )
      end
    end
  end
end
