# frozen_string_literal: true

module Wallets
  module Balance
    class IncreaseService < BaseService
      def initialize(wallet:, wallet_transaction:, reset_consumed_credits: false)
        super

        @wallet = wallet
        @wallet_transaction = wallet_transaction
        @reset_consumed_credits = reset_consumed_credits
      end

      def call
        amount_cents = wallet_transaction.amount_cents
        credits_amount = wallet_transaction.credit_amount

        update_params = {
          balance_cents: wallet.balance_cents + amount_cents,
          credits_balance: wallet.credits_balance + credits_amount,
          last_balance_sync_at: Time.current
        }

        if reset_consumed_credits
          update_params[:consumed_credits] = [0.0, wallet.consumed_credits - credits_amount].max
          update_params[:consumed_amount_cents] = [0, wallet.consumed_amount_cents - amount_cents].max
        end

        wallet.update!(update_params)

        Wallets::Balance::RefreshOngoingService.call(wallet:)

        after_commit { SendWebhookJob.perform_later("wallet.updated", wallet) }

        result.wallet = wallet
        result
      end

      private

      attr_reader :wallet, :wallet_transaction, :reset_consumed_credits
    end
  end
end
