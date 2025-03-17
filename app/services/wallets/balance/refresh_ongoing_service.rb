# frozen_string_literal: true

module Wallets
  module Balance
    class RefreshOngoingService < BaseService
      def initialize(wallet:)
        @wallet = wallet
        super
      end

      def call
        usage_amount_cents = customer.active_subscriptions.map do |subscription|
          customer_usage_result = ::Invoices::CustomerUsageService.call(customer:, subscription:)
          return customer_usage_result if customer_usage_result.failure?
          invoice = customer_usage_result.invoice
          progressive_billed_total = ::Subscriptions::ProgressiveBilledAmount.call(subscription: subscription).total_billed_amount_cents

          {
            total_usage_amount_cents: invoice.total_amount_cents,
            billed_usage_amount_cents: billed_usage_amount_cents(invoice, progressive_billed_total)
          }
        end

        @total_usage_amount_cents = usage_amount_cents.sum { |e| e[:total_usage_amount_cents] }
        @total_billed_usage_amount_cents = usage_amount_cents.sum { |e| e[:billed_usage_amount_cents] }
        update_params = wallet_update_params

        Wallets::Balance::UpdateOngoingService.call(wallet:, update_params:).raise_if_error!

        result.wallet = wallet
        result
      end

      private

      attr_reader :wallet, :total_usage_amount_cents, :total_billed_usage_amount_cents

      delegate :customer, to: :wallet

      def billed_usage_amount_cents(invoice, progressive_billed_total)
        paid_in_advance_fees = invoice.fees.select { |f| f.charge.pay_in_advance? && f.charge.invoiceable? }
        progressive_billed_total +
          # Invoice that is returned from CustomerUsageService includes the taxes in total_usage
          # so if the fees ae already paid, we should exclude fees AND their taxes
          paid_in_advance_fees.sum(&:amount_cents) +
          paid_in_advance_fees.sum(&:taxes_amount_cents)
      end

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
        ongoing_balance_cents.to_f.fdiv(currency.subunit_to_unit).fdiv(wallet.rate_amount)
      end
    end
  end
end
