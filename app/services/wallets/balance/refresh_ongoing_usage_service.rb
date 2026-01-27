# frozen_string_literal: true

module Wallets
  module Balance
    class RefreshOngoingUsageService < BaseService
      def initialize(wallet:, usage_amount_cents:, allocation_rules:)
        @wallet = wallet
        @usage_amount_cents = usage_amount_cents
        @allocation_rules = allocation_rules

        super
      end

      def call
        @total_usage_amount_cents = calculate_total_usage_with_limitation
        @total_billed_usage_amount_cents = calculate_total_billed_usage_amount_cents

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

      attr_reader :wallet, :total_usage_amount_cents, :total_billed_usage_amount_cents, :usage_amount_cents, :allocation_rules

      delegate :customer, to: :wallet

      def calculate_total_billed_usage_amount_cents
        usage_amount_cents.sum do |e|
          billed_progressive_invoices_amount_cents(e[:billed_progressive_invoice_subscriptions]) +
            billed_pay_in_advance_amount_cents(e[:invoice])
        end
      end

      def billed_progressive_invoices_amount_cents(invoice_subscriptions)
        fees = progressive_billing_fees(invoice_subscriptions)

        fees.sum do |fee|
          fee.taxes_amount_cents + fee.sub_total_excluding_taxes_amount_cents
        end
      end

      def progressive_billing_fees(invoice_subscriptions)
        fees = invoice_subscriptions.flat_map { it.invoice.fees }
        wallets_applicable_on_fees = assign_wallet_per_fee(fees)

        applicable_fees(fees, wallets_applicable_on_fees)
      end

      def applicable_fees(fees, fee_map)
        fees.select { |fee| fee_map[(fee.id || fee.object_id)] == wallet.id }
      end

      def invoice_pay_in_advance_fees(invoice)
        fees = invoice.fees.select { |f| f.charge.pay_in_advance? }
        wallets_applicable_on_fees = assign_wallet_per_fee(fees)

        applicable_fees(fees, wallets_applicable_on_fees)
      end

      def draft_invoices_fees
        fees = wallet.customer.invoices.draft.where.not(total_amount_cents: 0).flat_map(&:fees)
        wallets_applicable_on_fees = assign_wallet_per_fee(fees)

        applicable_fees(fees, wallets_applicable_on_fees)
      end

      def draft_invoices_total_amount_cents
        fees = draft_invoices_fees

        fees.sum do |fee|
          fee.amount_cents + fee.taxes_amount_cents - fee.precise_coupons_amount_cents
        end
      end

      def billed_pay_in_advance_amount_cents(invoice)
        paid_in_advance_fees = invoice_pay_in_advance_fees(invoice)
        # Invoice that is returned from CustomerUsageService includes the taxes in total_usage
        # so if the fees ae already paid, we should exclude fees AND their taxes
        paid_in_advance_fees.sum { |fee| fee.amount_cents + fee.taxes_amount_cents }
      end

      def wallet_update_params
        params = {
          ongoing_usage_balance_cents:,
          credits_ongoing_usage_balance:,
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

      def ongoing_usage_balance_cents
        @ongoing_usage_balance_cents ||= total_usage_amount_cents +
          draft_invoices_total_amount_cents -
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

      def assign_wallet_per_fee(fees)
        fee_wallet = {}

        fees.each do |fee|
          key = fee.id || fee.object_id

          applicable_wallets = Wallets::FindApplicableOnFeesService
            .call!(allocation_rules:, fee:, wallets: customer_wallets)
            .top_priority_wallet

          fee_wallet[key] = applicable_wallets.presence
        end

        fee_wallet
      end

      def customer_wallets
        @customer_wallets ||= customer.wallets.active.in_application_order
      end

      def calculate_total_usage_with_limitation
        all_fees = usage_amount_cents.flat_map { |usage| usage[:invoice].fees }
        wallets_applicable_on_fees = assign_wallet_per_fee(all_fees) # { fee_key => wallet_id }
        fees = applicable_fees(all_fees, wallets_applicable_on_fees)

        fees.sum { |fee| fee.amount_cents + fee.taxes_amount_cents }
      end
    end
  end
end
