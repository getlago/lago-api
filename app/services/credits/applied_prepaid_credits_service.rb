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

      # build a hash of remaining_amounts for each (fee_type and billable_metric_id) pair
      remaining_amounts = calculate_amounts_for_fees_by_type_and_bm

      ApplicationRecord.transaction do
        wallets.each do |wallet|
          if wallet_already_applied_on_invoice?(wallet)
            return result.service_failure!(code: "already_applied", message: "Prepaid credits already applied")
          end

          # returns applied amount on the fees_by_type_and_bm
          amount = applicable_wallet_amount(wallet, remaining_amounts)
          next if amount <= 0

          wallet_transaction = create_and_decrease!(wallet: wallet, amount_cents: amount, invoice:)
          result.wallet_transactions << wallet_transaction

          Utils::ActivityLog.produce(wallet_transaction, "wallet_transaction.created", after_commit: true)
          after_commit { SendWebhookJob.perform_later("wallet_transaction.created", wallet_transaction) }

          invoice.prepaid_credit_amount_cents += amount
          result.prepaid_credit_amount_cents += amount
        end

        invoice.save! if invoice.changed?
      end
      result
    end

    private

    attr_accessor :invoice, :wallets

    # build a hash of [fee_type, billable_metric_id] => remaining_amount
    def calculate_amounts_for_fees_by_type_and_bm
      remaining = Hash.new(0)

      invoice.fees.each do |f|
        cap = f.sub_total_excluding_taxes_amount_cents +
          f.taxes_precise_amount_cents -
          f.precise_credit_notes_amount_cents

        key = [f.fee_type, f.charge&.billable_metric_id]
        remaining[key] += cap
      end

      remaining
    end

    def applicable_wallet_amount(wallet, remaining_amounts_by_fee_type_and_bm)
      amount_left = wallet.balance_cents
      applied = 0

      eligible_fee_keys_for_wallet(wallet).each do |key|
        break if amount_left <= 0
        next if remaining_amounts_by_fee_type_and_bm[key].to_i <= 0

        take = [remaining_amounts_by_fee_type_and_bm[key], amount_left].min
        remaining_amounts_by_fee_type_and_bm[key] -= take
        amount_left -= take
        applied += take
      end

      applied
    end

    def eligible_fee_keys_for_wallet(wallet)
      all_fees = invoice.fees

      chosen = if wallet.limited_to_billable_metrics?
        fees_for_wallet_limited_to_bm(wallet, all_fees)
      elsif wallet.limited_fee_types?
        all_fees.select { |f| wallet.allowed_fee_types.include?(f.fee_type) }
      else
        all_fees
      end

      chosen.map { |f| [f.fee_type, f.charge&.billable_metric_id] }.uniq
    end

    def fees_for_wallet_limited_to_bm(wallet, all_fees)
      limited_to_bm_ids = wallet.wallet_targets.pluck(:billable_metric_id)
      fees_limited_by_bm = all_fees.select do |f|
        f.charge&.billable_metric_id && limited_to_bm_ids.include?(f.charge.billable_metric_id)
      end
      # a wallet can be limited only to BM or to BM AND some fee_types
      return fees_limited_by_bm unless wallet.limited_fee_types?

      remaining_fees = all_fees - fees_limited_by_bm
      # when wallet is limited to BM, it can't be applied to charge fees
      remaining_fees.reject! { |f| f.fee_type == "charge" }

      fees_limited_by_type = remaining_fees.select { |f| wallet.allowed_fee_types.include?(f.fee_type) }
      fees_limited_by_bm + fees_limited_by_type
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

    def wallet_already_applied_on_invoice?(wallet)
      invoice&.wallet_transactions&.where(wallet_id: wallet.id)&.exists?
    end
  end
end
