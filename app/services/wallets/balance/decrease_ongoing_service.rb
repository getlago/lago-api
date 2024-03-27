# frozen_string_literal: true

module Wallets
  module Balance
    class DecreaseOngoingService < BaseService
      def initialize(wallet:, credits_amount:)
        super

        @wallet = wallet
        @credits_amount = credits_amount
      end

      def call
        ongoing_usage_balance_cents = wallet.ongoing_usage_balance_cents

        wallet.update!(
          ongoing_usage_balance_cents: amount_cents,
          credits_ongoing_usage_balance: credits_amount,
          ongoing_balance_cents:,
          credits_ongoing_balance:
        )

        handle_threshold_top_up(ongoing_usage_balance_cents)

        result.wallet = wallet
        result
      end

      private

      attr_reader :wallet, :credits_amount

      def handle_threshold_top_up(ongoing_usage_balance_cents)
        threshold_rule = wallet.recurring_transaction_rules.where(rule_type: :threshold).first

        return if threshold_rule.nil? || wallet.credits_ongoing_balance > threshold_rule.threshold_credits
        #        return if amount_cents.positive? && ongoing_usage_balance_cents == amount_cents

        WalletTransactions::CreateJob.set(wait: 2.seconds).perform_later(
          organization_id: wallet.organization.id,
          wallet_id: wallet.id,
          paid_credits: threshold_rule.paid_credits.to_s,
          granted_credits: threshold_rule.granted_credits.to_s,
          source: :threshold
        )
      end

      def currency
        @currency ||= wallet.ongoing_balance.currency
      end

      def amount_cents
        @amount_cents ||= wallet.rate_amount * credits_amount * currency.subunit_to_unit
      end

      def pending_transactions
        @pending_transactions ||= wallet.wallet_transactions.pending
      end

      def ongoing_balance_cents
        [
          0,
          (pending_transactions.sum(:amount) * currency.subunit_to_unit) - amount_cents + wallet.balance_cents
        ].max
      end

      def credits_ongoing_balance
        [
          0,
          pending_transactions.sum(:credit_amount) - credits_amount + wallet.credits_balance
        ].max
      end
    end
  end
end
