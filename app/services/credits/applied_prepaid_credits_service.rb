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
      if wallets_already_applied?
        return result.service_failure!(code: "already_applied", message: "Prepaid credits already applied")
      end

      result.prepaid_credit_amount_cents ||= 0
      result.wallet_transactions ||= []

      ordered_remaining_amounts = calculate_amounts_for_fees_by_type_and_bm
      wallets.each do |wallet|
        wallet_fee_transactions = []
        wallet_targets_array = wallet.wallet_targets.map do |wt|
          if wt&.billable_metric_id
            ["charge", wt.billable_metric_id]
          end
        end
        wallet_types_array = wallet.allowed_fee_types

        ordered_remaining_amounts.each do |fee_key, remaining_amount|
          next if remaining_amount <= 0
          target_match = wallet_targets_array.include?(fee_key)
          type_match = wallet_types_array.include?(fee_key.first)
          unrestricted_wallet = wallet_targets_array.empty? && wallet_types_array.empty?
          should_apply_wallet_on_this_fee = target_match || type_match || unrestricted_wallet

          next unless should_apply_wallet_on_this_fee

          used_amount = wallet_fee_transactions.sum { |t| t[:amount_cents] }
          remaining_wallet_balance = wallet.balance_cents - used_amount
          next if remaining_wallet_balance <= 0

          transaction_amount = [remaining_amount, remaining_wallet_balance].min
          next if transaction_amount <= 0

          ordered_remaining_amounts[fee_key] -= transaction_amount
          wallet_fee_transactions << {
            fee_key: fee_key,
            amount_cents: transaction_amount
          }
        end

        total_amount_cents = wallet_fee_transactions.sum { |t| t[:amount_cents] }
        next if total_amount_cents <= 0

        wallet_transaction = create_and_decrease!(
          wallet: wallet,
          amount_cents: total_amount_cents,
          invoice: invoice
        )
        result.wallet_transactions << wallet_transaction
        result.prepaid_credit_amount_cents += total_amount_cents
        invoice.prepaid_credit_amount_cents += total_amount_cents
      end

      invoice.save! if invoice.changed?
      result
    end

    private

    attr_accessor :invoice, :wallets, :customer
    delegate :customer, to: :invoice

    def calculate_amounts_for_fees_by_type_and_bm
      remaining = Hash.new(0)

      invoice.fees.includes(:charge).find_each do |fee|
        cap = fee.sub_total_excluding_taxes_amount_cents +
          fee.taxes_precise_amount_cents -
          fee.precise_credit_notes_amount_cents

        next if cap <= 0
        key = [fee.fee_type, fee.charge&.billable_metric_id]
        remaining[key] += cap
      end

      remaining.sort_by { |_, v| -v }.to_h
    end

    def wallets_already_applied?
      return false unless invoice

      WalletTransaction.exists?(invoice_id: invoice.id, wallet_id: wallets.map(&:id))
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
        Utils::ActivityLog.produce(wallet_transaction, "wallet_transaction.created", after_commit: true)
        after_commit { SendWebhookJob.perform_later("wallet_transaction.created", wallet_transaction) }
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
  end
end
