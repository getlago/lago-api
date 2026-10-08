# frozen_string_literal: true

module Credits
  class AllocatePrepaidCreditsByWalletsService < BaseService
    Result = BaseResult[:wallet_transactions, :billable_metric_amounts]

    def initialize(invoice:)
      @invoice = invoice

      super(nil)
    end

    def call
      result.wallet_transactions ||= {}
      result.billable_metric_amounts ||= {}
      return result if wallets.empty?

      calculate_wallet_transactions
      result
    rescue ActiveRecord::RecordInvalid => e
      result.record_validation_failure!(record: e.record)
    end

    private

    attr_accessor :invoice

    delegate :customer, to: :invoice

    def calculate_wallet_transactions
      ordered_remaining_amounts = calculate_amounts_for_fees_by_type_and_bm
      remaining_invoice_amount = invoice.total_amount_cents

      wallets.each do |wallet|
        wallet.reload
        wallet_fee_transactions = []
        wallet_targets_array = wallet.wallet_targets.map do |wt|
          if wt&.billable_metric_id
            ["charge", wt.billable_metric_id]
          end
        end
        wallet_types_array = wallet.allowed_fee_types

        ordered_remaining_amounts.each do |fee_key, remaining_amount|
          next if remaining_amount <= 0

          next unless applicable_fee?(fee_key:, targets: wallet_targets_array, types: wallet_types_array, wallet:)

          used_amount = wallet_fee_transactions.sum { |t| t[:amount_cents] }
          remaining_wallet_balance = wallet.balance_cents - used_amount
          next if remaining_wallet_balance <= 0

          transaction_amount = [remaining_amount, remaining_wallet_balance, remaining_invoice_amount].min
          next if transaction_amount <= 0

          ordered_remaining_amounts[fee_key] -= transaction_amount
          remaining_invoice_amount -= transaction_amount
          wallet_fee_transactions << {
            fee_key: fee_key,
            amount_cents: transaction_amount
          }
        end
        total_amount_cents = wallet_fee_transactions.sum { |t| t[:amount_cents] }
        next if total_amount_cents <= 0
        result.wallet_transactions[wallet] = total_amount_cents
        result.billable_metric_amounts[wallet] = charge_amounts_by_subscription(wallet_fee_transactions)
      end
    end

    # What the wallet paid for charge usage, excluding taxes, per subscription and billable metric,
    # so usage can later be attributed to the wallets that paid for it. A fee key can span several
    # subscriptions of the invoice, so what the wallet paid for it is split between them by their
    # fees.
    def charge_amounts_by_subscription(wallet_fee_transactions)
      amounts = Hash.new { |hash, subscription_id| hash[subscription_id] = Hash.new(0) }

      wallet_fee_transactions.each do |transaction|
        fee_key = transaction[:fee_key]
        next unless fee_key.first == "charge"

        paid = transaction[:amount_cents].to_d
        shares = fee_shares[fee_key]
        total_cap = shares.values.sum { it[:cap] }

        shares.each do |subscription_id, share|
          amounts[subscription_id][fee_key.second] += tax_exclusive(share, paid * share[:cap] / total_cap)
        end
      end

      round_on_running_total(amounts)
    end

    # Rounded on the running total, so the parts never add up to more than the wallet transaction.
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

    # A fee's cap covers its taxes too, so what a wallet paid for a subscription's fees is split the
    # same way. Subscriptions sharing a fee key can be taxed differently, hence one share each.
    def tax_exclusive(share, amount)
      if share[:taxes].zero?
        amount
      else
        amount * share[:sub_total] / (share[:sub_total] + share[:taxes])
      end
    end

    # Per fee key and subscription: what its fees cap at, their amount before tax, and their tax.
    def fee_shares
      @fee_shares ||= Hash.new do |hash, fee_key|
        hash[fee_key] = Hash.new { |shares, subscription_id| shares[subscription_id] = {cap: 0, sub_total: 0, taxes: 0} }
      end
    end

    def calculate_amounts_for_fees_by_type_and_bm
      remaining = Hash.new(0)
      fees = invoice.persisted? ? invoice.fees.includes(:charge) : invoice.fees
      booked_tax = invoice.booked_tax_by_fee

      fees.each do |fee|
        next if fee.sub_total_excluding_taxes_amount_cents == 0

        cap = fee.sub_total_excluding_taxes_amount_cents +
          booked_tax.fetch(fee) -
          fee.precise_credit_notes_amount_cents

        next if cap <= 0
        key = [fee.fee_type, fee.charge&.billable_metric_id]
        if fee.organization.events_targeting_wallets_enabled? && fee.charge&.accepts_target_wallet
          key << fee.grouped_by&.dig("target_wallet_code")
        end
        remaining[key] += cap
        share = fee_shares[key][fee.subscription_id]
        share[:cap] += cap
        share[:sub_total] += fee.sub_total_excluding_taxes_amount_cents
        share[:taxes] += booked_tax.fetch(fee)
      end

      ordered = remaining.sort_by { |_, v| -v }.to_h
      reconcile_remaining_amounts(ordered)
    end

    def reconcile_remaining_amounts(ordered_remaining_amounts)
      return ordered_remaining_amounts if ordered_remaining_amounts.empty?

      precise_total = ordered_remaining_amounts.values.sum
      difference = invoice.total_amount_cents - precise_total

      # Only reconcile small rounding differences (at most 1 cent per fee bucket).
      return ordered_remaining_amounts if difference <= 0
      return ordered_remaining_amounts if difference > ordered_remaining_amounts.size

      largest_key = ordered_remaining_amounts.keys.first
      ordered_remaining_amounts[largest_key] += difference
      ordered_remaining_amounts
    end

    def applicable_fee?(fee_key:, targets:, types:, wallet:)
      target_wallet_code = fee_key[2]

      # If fee has target_wallet_code, only matching wallet can apply credits
      if target_wallet_code.present?
        return wallet.code == target_wallet_code
      end

      fee_key_without_wallet = fee_key.first(2)
      target_match = targets.include?(fee_key_without_wallet)
      type_match = types.include?(fee_key.first)
      unrestricted_wallet = targets.empty? && types.empty?

      target_match || type_match || unrestricted_wallet
    end

    def wallets
      @wallets ||= begin
        scope = customer.wallets.active.includes(:wallet_targets).with_positive_balance
        scope = scope.where(balance_currency: invoice.currency) if invoice.currency.present?
        scope.in_application_order
      end
    end
  end
end
