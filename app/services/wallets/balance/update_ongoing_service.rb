# frozen_string_literal: true

module Wallets
  module Balance
    class UpdateOngoingService < BaseService
      def initialize(wallet:, total_usage_amount_cents:, pay_in_advance_usage_amount_cents:)
        super

        @wallet = wallet
        @total_usage_amount_cents = total_usage_amount_cents
        @pay_in_advance_usage_amount_cents = pay_in_advance_usage_amount_cents
      end

      def call
        update_params = compute_update_params
        wallet.update!(update_params)

        after_commit do
          if update_params[:depleted_ongoing_balance] == true
            SendWebhookJob.perform_later('wallet.depleted_ongoing_balance', wallet)
          end

          ::Wallets::ThresholdTopUpService.call(wallet:)
        end

        result.wallet = wallet
        result
      end

      private

      attr_reader :wallet, :total_usage_amount_cents, :pay_in_advance_usage_amount_cents

      def compute_update_params
        params = {
          ongoing_usage_balance_cents: total_usage_amount_cents,
          credits_ongoing_usage_balance:,
          ongoing_balance_cents:,
          credits_ongoing_balance:,
          ready_to_be_refreshed: false
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

      def credits_ongoing_usage_balance
        total_usage_amount_cents.to_f.fdiv(currency.subunit_to_unit).fdiv(wallet.rate_amount)
      end

      def ongoing_balance_cents
        wallet.balance_cents - total_usage_amount_cents + pay_in_advance_usage_amount_cents
      end

      def credits_ongoing_balance
        ongoing_balance_cents.to_f.fdiv(currency.subunit_to_unit).fdiv(wallet.rate_amount)
      end
    end
  end
end
