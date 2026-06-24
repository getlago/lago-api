# frozen_string_literal: true

module Wallets
  module Balance
    # Distributes ongoing (unbilled) usage across the customer's wallets in priority order,
    # mirroring Credits::AllocatePrepaidCreditsByWalletsService. A wallet with an active
    # threshold-based recurring rule is the exception: it absorbs everything and may go
    # negative (no cascade) so the rule can fire and refill it.
    class AllocateOngoingUsageByWalletsService < BaseService
      Result = BaseResult[:wallet_allocations]

      def initialize(customer:, wallets:, current_usage_fees:, draft_invoices_fees:, progressive_billing_fees:, pay_in_advance_fees:)
        @customer = customer
        @wallets = wallets
        @current_usage_fees = current_usage_fees
        @draft_invoices_fees = draft_invoices_fees
        @progressive_billing_fees = progressive_billing_fees
        @pay_in_advance_fees = pay_in_advance_fees

        super
      end

      def call
        result.wallet_allocations = calculate_wallet_allocations
        result
      end

      private

      attr_reader :customer, :wallets, :current_usage_fees, :draft_invoices_fees,
        :progressive_billing_fees, :pay_in_advance_fees

      def calculate_wallet_allocations
        net_amounts = net_usage_by_fee_key
        budgets = currency_budgets(net_amounts)
        metas = wallets.map { |wallet| wallet_meta(wallet) }
        allocations = wallets.index_with(0)

        allocatable_pool(net_amounts).each do |fee_key, key_amount|
          currency = fee_key.last
          remaining = [key_amount, budgets[currency]].min
          applicable = metas.select { |meta| applicable_fee?(fee_key:, wallet: meta[:wallet], targets: meta[:targets], types: meta[:types]) }

          applicable.each_with_index do |meta, index|
            break if remaining <= 0

            if meta[:threshold] || index == applicable.length - 1
              # A threshold wallet absorbs everything so its rule can refill it; the last
              # applicable wallet absorbs the overflow. Both are allowed to go negative.
              take = remaining
            else
              room = meta[:balance] - allocations[meta[:wallet]]
              next if room <= 0
              take = [remaining, room].min
            end

            allocations[meta[:wallet]] += take
            remaining -= take
            budgets[currency] -= take
          end
        end

        allocations
      end

      def wallet_meta(wallet)
        threshold = threshold_wallet?(wallet)
        {
          wallet:,
          targets: wallet.wallet_targets.filter_map { |wt| ["charge", wt.billable_metric_id] if wt.billable_metric_id },
          types: wallet.allowed_fee_types,
          threshold:,
          # Re-read the balance so a concurrent pay-in-advance DecreaseService can't make us cap
          # against a stale value. Balance only, to keep the eager-loaded associations.
          balance: threshold ? 0 : Wallet.where(id: wallet.id).pick(:balance_cents)
        }
      end

      # Net the fee buckets into a signed amount per fee key. Keys whose net is <= 0
      # (already fully billed) cannot receive allocations, but their negative nets still
      # reduce the per-currency budget the same way billing credits reduce the invoice total.
      def net_usage_by_fee_key
        net_amounts = Hash.new(0)

        add_to_pool(net_amounts, current_usage_fees) { |fee| fee.amount_cents + fee.taxes_amount_cents }
        add_to_pool(net_amounts, draft_invoices_fees) { |fee| fee.amount_cents + fee.taxes_amount_cents - fee.precise_coupons_amount_cents }
        add_to_pool(net_amounts, progressive_billing_fees) { |fee| -(fee.sub_total_excluding_taxes_amount_cents + fee.taxes_amount_cents) }
        add_to_pool(net_amounts, pay_in_advance_fees) { |fee| -(fee.amount_cents + fee.taxes_amount_cents) }

        net_amounts
      end

      def allocatable_pool(net_amounts)
        net_amounts
          .select { |_, amount| amount.positive? }
          # Ties broken by fee key so the allocation order is stable across refreshes.
          .sort_by { |fee_key, amount| [-amount, fee_key.map(&:to_s)] }
          .to_h
      end

      # Mirrors billing's remaining_invoice_amount: an over-billed key's negative net offsets
      # the other keys in its currency, the same way credits offset the invoice at billing.
      def currency_budgets(net_amounts)
        budgets = Hash.new(0)
        net_amounts.each { |fee_key, amount| budgets[fee_key.last] += amount }
        budgets.transform_values! { |amount| [amount, 0].max }
      end

      def add_to_pool(remaining, fees)
        fees.each { |fee| remaining[fee_key(fee)] += yield(fee) }
      end

      def fee_key(fee)
        target_wallet_code = if fee_targeting_wallets_enabled? && fee.charge&.accepts_target_wallet
          fee.grouped_by&.dig("target_wallet_code")
        end

        [fee.fee_type, fee.charge&.billable_metric_id, target_wallet_code, fee.amount_currency]
      end

      def applicable_fee?(fee_key:, wallet:, targets:, types:)
        fee_type, _billable_metric_id, target_wallet_code, currency = fee_key

        return false unless wallet.balance_currency == currency
        return wallet.code == target_wallet_code if target_wallet_code.present?

        target_match = targets.include?(fee_key.first(2))
        type_match = types.include?(fee_type)
        unrestricted_wallet = targets.empty? && types.empty?

        target_match || type_match || unrestricted_wallet
      end

      def threshold_wallet?(wallet)
        wallet.recurring_transaction_rules.any? { |rule| rule.currently_active? && rule.threshold? }
      end

      def fee_targeting_wallets_enabled?
        return @fee_targeting_wallets_enabled if defined?(@fee_targeting_wallets_enabled)

        @fee_targeting_wallets_enabled = customer.organization.events_targeting_wallets_enabled?
      end
    end
  end
end
