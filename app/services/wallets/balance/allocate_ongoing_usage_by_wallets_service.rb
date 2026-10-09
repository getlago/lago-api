# frozen_string_literal: true

module Wallets
  module Balance
    # Distributes ongoing (unbilled) usage across the customer's wallets in priority order,
    # mirroring Credits::AllocatePrepaidCreditsByWalletsService. A wallet with an active
    # threshold-based recurring rule is the exception: it absorbs everything and may go
    # negative (no cascade) so the rule can fire and refill it.
    class AllocateOngoingUsageByWalletsService < BaseService
      Result = BaseResult[:wallet_allocations, :billable_metric_amounts]

      # with_billable_metric_amounts: the per-metric split runs on every refresh and only streamed
      # usage reads it, so callers ask for it when the organization streams.
      def initialize(customer:, wallets:, current_usage_fees:, draft_invoices_fees:, progressive_billing_fees:, pay_in_advance_fees:,
        with_billable_metric_amounts: false)
        @customer = customer
        @wallets = wallets
        @current_usage_fees = current_usage_fees
        @draft_invoices_fees = draft_invoices_fees
        @progressive_billing_fees = progressive_billing_fees
        @pay_in_advance_fees = pay_in_advance_fees
        @with_billable_metric_amounts = with_billable_metric_amounts

        super
      end

      def call
        result.billable_metric_amounts = with_billable_metric_amounts ? wallets.index_with { empty_billable_metric_amounts } : {}
        result.wallet_allocations = calculate_wallet_allocations
        result.billable_metric_amounts.transform_values! { |amounts| round_on_running_total(amounts) }
        result
      end

      private

      attr_reader :customer, :wallets, :current_usage_fees, :draft_invoices_fees,
        :progressive_billing_fees, :pay_in_advance_fees, :with_billable_metric_amounts

      def calculate_wallet_allocations
        net_amounts = net_usage_by_fee_key
        budgets = currency_budgets(net_amounts)
        balances = fresh_balances
        metas = wallets.map { |wallet| wallet_meta(wallet, balances) }
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

        if with_billable_metric_amounts
          cover_by_period(metas, balances)
        end

        allocations
      end

      # What billing will take from each wallet, period by period: last period's draft invoice is
      # finalized before this period's usage is billed, so every fee of an older period is covered
      # before any of a newer one, larger amounts first within a period. Each period is budgeted on
      # its own, like the invoice it ends up on, and wallets give up to their real balance, cascading
      # past threshold wallets: the ongoing balance lets a wallet go negative, billing never does.
      def cover_by_period(metas, balances)
        budgets = coverage_budgets
        covered = wallets.index_with(0)

        coverage_buckets.each do |bucket, amount|
          budget_key = [bucket.first, bucket.last.last]
          applicable = metas.select { |meta| applicable_fee?(fee_key: bucket.last, wallet: meta[:wallet], targets: meta[:targets], types: meta[:types]) }
          budgets[budget_key] -= cover(bucket, [amount, budgets[budget_key]].min, applicable, balances, covered)
        end
      end

      # Positive nets per billing period and fee key, oldest period first, then largest amount, with
      # ties broken by fee key so the order is stable across refreshes.
      def coverage_buckets
        period_nets
          .flat_map { |fee_key, by_period| by_period.map { |period, by_subscription| [[period, fee_key], by_subscription.values.sum] } }
          .select { |_bucket, amount| amount.positive? }
          .sort_by { |(period, fee_key), amount| [period.to_s, -amount, fee_key.map(&:to_s)] }
      end

      # Per billing period and currency, mirroring billing's remaining_invoice_amount on the invoice
      # the period ends up on: an over-billed key offsets the others of its period.
      def coverage_budgets
        budgets = Hash.new(0)

        period_nets.each do |fee_key, by_period|
          by_period.each { |period, by_subscription| budgets[[period, fee_key.last]] += by_subscription.values.sum }
        end

        budgets.transform_values! { |amount| [amount, 0].max }
      end

      def cover(bucket, amount, applicable, balances, covered)
        period, fee_key = bucket
        uncovered = amount

        applicable.each do |meta|
          break if uncovered <= 0

          wallet = meta[:wallet]
          take = [uncovered, balances.fetch(wallet.id, 0) - covered[wallet]].min
          next if take <= 0

          covered[wallet] += take
          uncovered -= take
          record_coverage(wallet, fee_key, period, take) if fee_key.first == "charge"
        end

        amount - uncovered
      end

      # Per subscription, then billing period, then billable metric. The period is kept because the
      # pool also holds the previous period's draft invoices during their grace period.
      def empty_billable_metric_amounts
        Hash.new { |by_subscription, subscription_id| by_subscription[subscription_id] = Hash.new { |by_period, period| by_period[period] = Hash.new(0) } }
      end

      # Within a period, what a wallet covers for a fee key is split between subscriptions by what each
      # still has to cover.
      def record_coverage(wallet, fee_key, period, take)
        nets = period_nets[fee_key][period].select { |_subscription_id, net| net.positive? }
        total = nets.values.sum

        nets.each do |subscription_id, net|
          result.billable_metric_amounts[wallet][subscription_id][period][fee_key.second] +=
            tax_exclusive(fee_key, subscription_id, period, take.to_d * net / total)
        end
      end

      def period(fee)
        Time.zone.parse(fee.properties["charges_from_datetime"].to_s)&.utc&.iso8601
      end

      # Rounded on the running total, so the parts never add up to more than the wallet covers.
      def round_on_running_total(amounts)
        running_total = 0

        amounts.transform_values do |by_period|
          by_period.transform_values do |by_metric|
            by_metric.transform_values do |amount|
              rounded = (running_total + amount).round - running_total.round
              running_total += amount
              rounded
            end
          end
        end
      end

      # Usage and draft fees enter the pool with their taxes, so what a wallet covers for a
      # subscription's fees is split the same way to keep the taxes out. Subscriptions sharing a fee
      # key, and periods, can be taxed differently, so each keeps its own ratio.
      def tax_exclusive(fee_key, subscription_id, period, amount)
        taxes = taxes_by_share[[fee_key, subscription_id, period]]
        sub_total = sub_totals_by_share[[fee_key, subscription_id, period]]

        if taxes.zero?
          amount
        else
          amount * sub_total / (sub_total + taxes)
        end
      end

      # A share is a subscription's fees for a fee key in one period.
      def sub_totals_by_share
        @sub_totals_by_share ||= sum_by_share { |fee| fee.amount_cents - fee.precise_coupons_amount_cents }
      end

      def taxes_by_share
        @taxes_by_share ||= sum_by_share(&:taxes_amount_cents)
      end

      def sum_by_share
        (current_usage_fees + draft_invoices_fees).each_with_object(Hash.new(0)) do |fee, sums|
          sums[[fee_key(fee), fee.subscription_id, period(fee)]] += yield(fee)
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
          period_nets[key][period(fee)][fee.subscription_id] += amount if with_billable_metric_amounts
        end
      end

      # Signed nets per fee key, billing period and subscription.
      def period_nets
        @period_nets ||= Hash.new { |by_key, fee_key| by_key[fee_key] = Hash.new { |by_period, period| by_period[period] = Hash.new(0) } }
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
