# frozen_string_literal: true

module Wallets
  module Balance
    class DecreaseService < BaseService
      def initialize(wallet:, wallet_transaction:, skip_refresh: true)
        @wallet = wallet
        @wallet_transaction = wallet_transaction
        @skip_refresh = skip_refresh

        super
      end

      def call
        credits_amount = wallet_transaction.credit_amount
        currency = wallet.currency_for_balance

        wallet.update!(
          balance_cents: ((wallet.credits_balance - credits_amount) * wallet.rate_amount * currency.subunit_to_unit).floor,
          credits_balance: wallet.credits_balance - credits_amount,
          last_balance_sync_at: Time.zone.now,
          consumed_credits: wallet.consumed_credits + credits_amount,
          consumed_amount_cents: ((wallet.consumed_credits + credits_amount) * wallet.rate_amount * currency.subunit_to_unit).floor,
          last_consumed_credit_at: Time.current
        )

        unless skip_refresh
          Wallets::Balance::RefreshOngoingService.call(
            wallet:,
            include_generating_invoices: true
          )
        end

        after_commit { SendWebhookJob.perform_later("wallet.updated", wallet) }

        result.wallet = wallet
        result
      end

      private

      attr_reader :wallet, :wallet_transaction, :skip_refresh
    end
  end
end
