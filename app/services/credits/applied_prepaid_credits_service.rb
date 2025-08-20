# frozen_string_literal: true

module Credits
  class AppliedPrepaidCreditsService < BaseService
    MAX_WALLET_DECREASE_ATTEMPTS = 5

    def initialize(invoice:, wallets:)
      @invoice = invoice
      @wallets = wallets
      super(nil)
    end

    def call
      result.prepaid_credit_amount_cents ||= 0
      result.wallet_transactions ||= []

      remaining = build_buckets

      ApplicationRecord.transaction do
        wallets.each do |wallet|
          byebug
          next if already_applied_for_wallet?(wallet)

          amount = distribute_from_buckets(wallet, remaining)
          next if amount <= 0

          wallet_transaction = create_and_decrease!(wallet: wallet, amount_cents: amount, invoice:)
          result.wallet_transactions << wallet_transaction

          invoice.prepaid_credit_amount_cents += amount
          result.prepaid_credit_amount_cents  += amount
        end
      end

      #after_commit { SendWebhookJob.perform_later("wallet_transaction.created", result.wallet_transaction) }
      result
    end

    private

    attr_accessor :invoice, :wallets

    def build_buckets
      remaining = Hash.new(0)

      invoice.fees.each do |f|
        cap = f.sub_total_excluding_taxes_amount_cents +
              f.taxes_amount_cents -
              f.precise_credit_notes_amount_cents

        key = [f.fee_type, f.charge&.billable_metric_id]
        remaining[key] += cap
      end

      remaining
    end

    def eligible_buckets_for(wallet)
      all_fees = invoice.fees.to_a

      if wallet.limited_to_billable_metrics?
        bm_ids = wallet.wallet_targets.pluck(:billable_metric_id)

        bm_limited_fees = all_fees.select do |f|
          f.charge&.billable_metric_id && bm_ids.include?(f.charge.billable_metric_id)
        end

        remaining_fees = all_fees - bm_limited_fees
        remaining_fees.reject! { |f| f.fee_type == "charge" }

        fee_type_limited_fees =
          if wallet.limited_fee_types?
            remaining_fees.select { |f| wallet.allowed_fee_types.include?(f.fee_type) }
          else
            [] # when BM-limited only, we don't add remaining fees
          end

        chosen = bm_limited_fees + fee_type_limited_fees
      elsif wallet.limited_fee_types?
        chosen = all_fees.select { |f| wallet.allowed_fee_types.include?(f.fee_type) }
      else
        chosen = all_fees
      end

      chosen.map { |f| [f.fee_type, f.charge&.billable_metric_id] }.uniq
    end

    def distribute_from_buckets(wallet, remaining)
      amount_left = wallet.balance_cents
      applied     = 0

      eligible_buckets_for(wallet).each do |bucket|
        break if amount_left <= 0
        next if remaining[bucket].to_i <= 0

        take = [remaining[bucket], amount_left].min
        remaining[bucket] -= take
        amount_left       -= take
        applied           += take
      end

      applied
    end

    def already_applied_for_wallet?(wallet)
      invoice&.wallet_transactions&.where(wallet_id: wallet.id)&.exists?
    end

    def create_and_decrease!(wallet:, amount_cents:, invoice:)
      wallet_credit = WalletCredit.from_amount_cents(wallet: wallet, amount_cents: amount_cents)

      wallet_transaction = WalletTransactions::CreateService.call!(
        wallet:,
        wallet_credit:,
        invoice_id: invoice.id,
        transaction_type: :outbound,
        status: :settled,
        settled_at: Time.current,
        transaction_status: :invoiced
      ).wallet_transaction

      # Decrease balance with retry (optimistic locking)
      decrease_attempt = 0
      begin
        decrease_attempt += 1
        Wallets::Balance::DecreaseService.new(wallet:, wallet_transaction: wallet_transaction).call
      rescue ActiveRecord::StaleObjectError
        if decrease_attempt <= MAX_WALLET_DECREASE_ATTEMPTS
          sleep(rand(0.1..0.5))
          wallet.reload
          retry
        end
        raise
      end

      wallet_transaction
    end

    def restricted_wallets?
      wallets.any? { |w| w.limited_fee_types? || w.limited_to_billable_metrics? }
    end
  end
end
