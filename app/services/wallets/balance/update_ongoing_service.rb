# frozen_string_literal: true

module Wallets
  module Balance
    class UpdateOngoingService < BaseService
      def initialize(wallet:, usage_credits_amount:)
        super

        @wallet = wallet
        @usage_credits_amount = usage_credits_amount
      end

      def call
        ongoing_usage_balance_cents = wallet.ongoing_usage_balance_cents
        update_params = compute_update_params
        wallet.update!(update_params)
        wallet.reload

        if update_params[:depleted_ongoing_balance] == true
          SendWebhookJob.perform_later('wallet.depleted_ongoing_balance', wallet)
        end

        Wallets::TopUpService.call(wallet:)

        result.wallet = wallet
        result
      end

      private

      attr_reader :wallet, :usage_credits_amount

      def compute_update_params
        params = {
          ongoing_usage_balance_cents: usage_amount_cents,
          credits_ongoing_usage_balance: usage_credits_amount,
          ongoing_balance_cents:,
          credits_ongoing_balance:
        }

        if !wallet.depleted_ongoing_balance? && ongoing_balance_cents <= 0
          params[:depleted_ongoing_balance] = true
        elsif wallet.depleted_ongoing_balance? && ongoing_balance_cents.positive?
          params[:depleted_ongoing_balance] = false
        end

        params
      end

      def currency
        @currency ||= wallet.ongoing_balance.currency
      end

      def usage_amount_cents
        @usage_amount_cents ||= wallet.rate_amount * usage_credits_amount * currency.subunit_to_unit
      end

      def ongoing_balance_cents
        wallet.balance_cents - usage_amount_cents
      end

      def credits_ongoing_balance
        wallet.credits_balance - usage_credits_amount
      end
    end
  end
end
