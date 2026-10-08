# frozen_string_literal: true

module Wallets
  module Balance
    # Distributes ongoing (unbilled) usage across the customer's wallets in priority order,
    # mirroring Credits::AllocatePrepaidCreditsByWalletsService. A wallet with an active
    # threshold-based recurring rule is the exception: it absorbs everything and may go
    # negative (no cascade) so the rule can fire and refill it.
    class AllocateOngoingUsageByWalletsService < BaseService
      Result = BaseResult[:wallet_allocations, :billable_metric_amounts]

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
        result.billable_metric_amounts = wallets.index_with { Hash.new { |hash, subscription_id| hash[subscription_id] = Hash.new(0) } }
        result.wallet_allocations = calculate_wallet_allocations
        result.billable_metric_amounts.transform_values! { |amounts| round_on_running_total(amounts) }
        result
      end

      private

      attr_reader :customer, :wallets, :current_usage_fees, :draft_invoices_fees,
        :progressive_billing_fees, :pay_in_advance_fees

      def calculate_wallet_allocations
        net_amounts = net_usage_by_fee_key
        budgets = currency_budgets(net_amounts)
        balances = fresh_balances
        metas = wallets.map { |wallet| wallet_meta(wallet, balances) }
        allocations = wallets.index_with(0)
        covered = wallets.index_with(0)
        # Billing only takes from the invoice what wallets actually pay, so the split keeps its own
        # budget, reduced by what was covered rather than by what the ongoing balance absorbed.
        coverage_budgets = budgets.dup

        allocatable_pool(net_amounts).each do |fee_key, key_amount|
          currency = fee_key.last
          remaining = [key_amount, budgets[currency]].min
          applicable = metas.select { |meta| applicable_fee?(fee_key:, wallet: meta[:wallet], targets: meta[:targets], types: meta[:types]) }
          coverage_budgets[currency] -= cover(fee_key, [key_amount, coverage_budgets[currency]].min, applicable, balances, covered)

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

      # What billing would take from each wallet for this key: wallets in priority order, each up to
      # its real balance, cascading past threshold wallets, and leaving the rest uncovered. The
      # ongoing balance lets a wallet go negative so its rule can refill it; billing never does.
      def cover(fee_key, amount, applicable, balances, covered)
        uncovered = amount

        applicable.each do |meta|
          break if uncovered <= 0

          wallet = meta[:wallet]
          take = [uncovered, balances.fetch(wallet.id, 0) - covered[wallet]].min
          next if take <= 0

          covered[wallet] += take
          uncovered -= take
          record_coverage(wallet, fee_key, take) if fee_key.first == "charge"
        end

        amount - uncovered
      end

      # A fee key can span several subscriptions, so what a wallet covers for it is split between
      # them by what each still has to cover.
      def record_coverage(wallet, fee_key, take)
        nets = nets_by_fee_key_and_subscription[fee_key].select { |_subscription_id, net| net.positive? }
        total = nets.values.sum

        nets.each do |subscription_id, net|
          share = take.to_d * net / total
          result.billable_metric_amounts[wallet][subscription_id][fee_key.second] += tax_exclusive(fee_key, subscription_id, share)
        end
      end

      # Rounded on the running total, so the parts never add up to more than the wallet covers.
      def round_on_running_total(amounts)
        running_total = 0

        amounts.transform_values do |by_metric|
          by_metric.transform_values do |amount|
            rounded = (running_total + amount).round - running_total.round
            running_total += amount
            rounded
          end
        end
      end

      # Usage and draft fees enter the pool with their taxes, so what a wallet covers for a
      # subscription's fees is split the same way to keep the taxes out. Subscriptions sharing a fee
      # key can be taxed differently, so each keeps its own ratio.
      def tax_exclusive(fee_key, subscription_id, amount)
        taxes = taxes_by_fee_key_and_subscription[[fee_key, subscription_id]]
        sub_total = sub_totals_by_fee_key_and_subscription[[fee_key, subscription_id]]

        if taxes.zero?
          amount
        else
          amount * sub_total / (sub_total + taxes)
        end
      end

      def sub_totals_by_fee_key_and_subscription
        @sub_totals_by_fee_key_and_subscription ||= sum_by_fee_key_and_subscription { |fee| fee.amount_cents - fee.precise_coupons_amount_cents }
      end

      def taxes_by_fee_key_and_subscription
        @taxes_by_fee_key_and_subscription ||= sum_by_fee_key_and_subscription(&:taxes_amount_cents)
      end

      def sum_by_fee_key_and_subscription
        (current_usage_fees + draft_invoices_fees).each_with_object(Hash.new(0)) do |fee, sums|
          sums[[fee_key(fee), fee.subscription_id]] += yield(fee)
        end
      end

      def wallet_meta(wallet, balances)
        threshold = threshold_wallet?(wallet)
        {
          wallet:,
          targets: wallet.wallet_targets.filter_map { |wt| ["charge", wt.billable_metric_id] if wt.billable_metric_id },
          types: wallet.allowed_fee_types,
          threshold:,
          balance: threshold ? 0 : balances.fetch(wallet.id, 0)
        }
      end

      # Re-read balances so a concurrent pay-in-advance DecreaseService can't make us cap
      # against stale in-memory values: one query for all wallets, one consistent snapshot.
      def fresh_balances
        Wallet.where(id: wallets.map(&:id)).pluck(:id, :balance_cents).to_h
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
        fees.each do |fee|
          key = fee_key(fee)
          amount = yield(fee)
          remaining[key] += amount
          nets_by_fee_key_and_subscription[key][fee.subscription_id] += amount
        end
      end

      def nets_by_fee_key_and_subscription
        @nets_by_fee_key_and_subscription ||= Hash.new { |hash, fee_key| hash[fee_key] = Hash.new(0) }
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
