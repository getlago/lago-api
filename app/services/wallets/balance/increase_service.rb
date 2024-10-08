# frozen_string_literal: true

module Wallets
  module Balance
    class IncreaseService < BaseService
      MAX_RETRIES = 1

      def initialize(wallet:, credits_amount:, reset_consumed_credits: false)
        super

        @wallet = wallet
        @credits_amount = credits_amount
        @reset_consumed_credits = reset_consumed_credits
        @retries = 0
      end

      def call
        ActiveRecord::Base.transaction do
          currency = wallet.balance.currency
          amount_cents = wallet.rate_amount * credits_amount * currency.subunit_to_unit

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
        end

        result.wallet = wallet
        result
      rescue ActiveRecord::StaleObjectError
        @retries += 1

        if @retries <= MAX_RETRIES
          wallet.reload

          retry
        end

        result.service_failure!(code: 'race_condition_error', message: '')
      end

      private

      attr_reader :wallet, :credits_amount, :reset_consumed_credits
    end
  end
end
