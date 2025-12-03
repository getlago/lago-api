# frozen_string_literal: true

module Credits
  class AppliedPrepaidCreditsService < BaseService
    DEFAULT_MAX_WALLET_DECREASE_ATTEMPTS = 6

    def initialize(invoice:, wallets:, max_wallet_decrease_attempts: DEFAULT_MAX_WALLET_DECREASE_ATTEMPTS)
      @invoice = invoice
      @wallet = wallets.first
      @max_wallet_decrease_attempts = max_wallet_decrease_attempts
      raise ArgumentError, "max_wallet_decrease_attempts must be between 1 and #{DEFAULT_MAX_WALLET_DECREASE_ATTEMPTS} (inclusive)" if max_wallet_decrease_attempts < 1 || max_wallet_decrease_attempts > DEFAULT_MAX_WALLET_DECREASE_ATTEMPTS

      super(nil)
    end

    activity_loggable(
      action: "wallet_transaction.created",
      record: -> { result.wallet_transaction }
    )

    def call
      if already_applied?
        return result.service_failure!(code: "already_applied", message: "Prepaid credits already applied")
      end

      amount_cents = compute_amount

      ApplicationRecord.transaction do
        wallet_transaction = create_wallet_transaction(amount_cents)
        result.wallet_transaction = wallet_transaction
        amount_cents = wallet_transaction.amount_cents

        with_optimistic_lock_retry(wallet) do
          Wallets::Balance::DecreaseService.call(wallet:, wallet_transaction:)
        end
      end

      result.prepaid_credit_amount_cents = amount_cents
      invoice.prepaid_credit_amount_cents += amount_cents

      SendWebhookJob.perform_after_commit("wallet_transaction.created", result.wallet_transaction)

      result
    rescue ActiveRecord::RecordInvalid => e
      result.record_validation_failure!(record: e.record)
    end

    private

    attr_accessor :invoice, :wallet, :max_wallet_decrease_attempts

    delegate :balance_cents, to: :wallet

    def create_wallet_transaction(amount_cents)
      wallet_credit = WalletCredit.from_amount_cents(wallet:, amount_cents:)

      result = WalletTransactions::CreateService.call!(
        wallet:,
        wallet_credit:,
        invoice_id: invoice.id,
        transaction_type: :outbound,
        status: :settled,
        settled_at: Time.current,
        transaction_status: :invoiced
      )
      result.wallet_transaction
    end

    def with_optimistic_lock_retry(wallet, &block)
      decrease_attempt = 0
      begin
        decrease_attempt += 1
        yield
      rescue ActiveRecord::StaleObjectError
        if decrease_attempt < max_wallet_decrease_attempts
          sleep(rand(0.1..0.5))
          wallet.reload # Make sure the wallet is reloaded before retrying
          retry
        end

        raise
      end
    end

    def already_applied?
      invoice&.wallet_transactions&.exists?
    end

    def compute_amount
      if wallet.limited_to_billable_metrics? && billable_metric_limited_fees
        bm_limited_fees = billable_metric_limited_fees
        remaining_fees = invoice.fees - bm_limited_fees
        remaining_fees = remaining_fees.reject { |fee| fee.fee_type == "charge" }
      else
        bm_limited_fees = []
        remaining_fees = invoice.fees
      end

      fee_type_limited_fees = if wallet.limited_fee_types?
        remaining_fees.filter { |fee| wallet.allowed_fee_types.include?(fee.fee_type) }
      elsif wallet.limited_to_billable_metrics? && billable_metric_limited_fees
        []
      else
        remaining_fees
      end

      if wallet.limited_fee_types? || wallet.limited_to_billable_metrics?
        [balance_cents, limited_fees_total(bm_limited_fees + fee_type_limited_fees)].min
      else
        [balance_cents, invoice.total_amount_cents].min
      end
    end

    def billable_metric_limited_fees
      @billable_metric_limited_fees ||= invoice.fees
        .joins(charge: :billable_metric)
        .where(billable_metric: {id: wallet.wallet_targets.pluck(:billable_metric_id)})
    end

    def limited_fees_total(applicable_fees)
      applicable_fees.sum do |f|
        f.sub_total_excluding_taxes_precise_amount_cents + f.taxes_precise_amount_cents - f.precise_credit_notes_amount_cents
      end
    end
  end
end
