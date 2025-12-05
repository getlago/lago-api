# frozen_string_literal: true

module Wallets
  module Balance
    class RefreshOngoingUsageService < BaseService
      def initialize(wallet:, usage_amount_cents:)
        @wallet = wallet
        @usage_amount_cents = usage_amount_cents

        super
      end

      def call
        @total_usage_amount_cents = calculate_total_usage_with_limitation
        @total_billed_usage_amount_cents = usage_amount_cents.sum { |e| e[:billed_usage_amount_cents] }
        # Before this service is called, the wallet is already loaded in the memory. If while calculating current usage we received
        # a pay_in_advance_fee, wallet will be updated by Wallets::Balance::DecreaseService and current wallet version will throw an
        # `Attempted to update a stale object` error. To avoid this, we reload the wallet before updating it.
        wallet.reload
        update_params = wallet_update_params

        Wallets::Balance::UpdateOngoingService.call(wallet:, update_params:).raise_if_error!

        result.wallet = wallet
        result
      end

      private

      attr_reader :wallet, :total_usage_amount_cents, :total_billed_usage_amount_cents, :usage_amount_cents

      delegate :customer, to: :wallet

      def wallet_update_params
        params = {
          ongoing_usage_balance_cents:,
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

      def ongoing_usage_balance_cents
        @ongoing_usage_balance_cents ||= total_usage_amount_cents +
          wallet.customer.invoices.draft.sum(:total_amount_cents) -
          total_billed_usage_amount_cents
      end

      def credits_ongoing_usage_balance
        ongoing_usage_balance_cents.to_f.fdiv(currency.subunit_to_unit).fdiv(wallet.rate_amount)
      end

      def ongoing_balance_cents
        @ongoing_balance_cents ||= wallet.balance_cents - ongoing_usage_balance_cents
      end

      def credits_ongoing_balance
        wallet.credits_balance - credits_ongoing_usage_balance
      end

      def calculate_total_usage_with_limitation
        return usage_amount_cents.sum { |e| e[:total_usage_amount_cents] } unless wallet.limited_to_billable_metrics?

        # current usage fees are not persisted so we can't use join
        all_fees = usage_amount_cents.flat_map { |usage| usage[:invoice].fees }
        charge_ids = Charge.where(id: all_fees.map(&:charge_id)).where(billable_metric_id: wallet.wallet_targets.pluck(:billable_metric_id)).pluck(:id)

        return usage_amount_cents.sum { |e| e[:total_usage_amount_cents] } if charge_ids.empty?

        all_fees
          .select { |f| charge_ids.include?(f.charge_id) }
          .sum { |f| f.amount_cents + f.taxes_amount_cents }
      end
    end
  end
end
