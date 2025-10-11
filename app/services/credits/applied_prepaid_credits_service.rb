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

      wallet_allocations = Wallets::BuildAllocationRulesService.call!(customer:)
      wallet_transactions = Hash.new { |h, k| h[k] = [] }

      invoice.fees.each do |fee|
        fee_remaining_amount = fee_amount(fee)
        wallets_sorted = Wallets::FindApplicableOnFeesService.call!(
          wallet_allocation: wallet_allocations.allocation_rules,
          fee: fee
        )

        wallets_sorted.applicable_wallets.each do |wallet_id|
          break if fee_remaining_amount <= 0
          wallet_to_use = wallets.find { |w| w.id == wallet_id }
          next unless wallet_to_use

          used_amount = wallet_transactions[wallet_id].sum { |t| t[:amount_cents] }
          remaining_wallet_balance = wallet_to_use.balance_cents - used_amount
          next if remaining_wallet_balance <= 0

          transaction_amount = [fee_remaining_amount, remaining_wallet_balance].min
          fee_remaining_amount -= transaction_amount
          wallet_transactions[wallet_id] << {fee_id: fee.id, amount_cents: transaction_amount}
        end
      end

      wallet_transactions.each do |wallet_id, fees|
        total_amount_cents = fees.sum { |t| t[:amount_cents].to_i }
        wallet = wallets.find { |w| w.id == wallet_id }
        next unless wallet

        wallet_transaction = create_and_decrease!(
          wallet: wallet,
          amount_cents: total_amount_cents,
          invoice: invoice
        )
        result.wallet_transactions << wallet_transaction
        result.prepaid_credit_amount_cents += total_amount_cents
        invoice.prepaid_credit_amount_cents += total_amount_cents

        Utils::ActivityLog.produce(wallet_transaction, "wallet_transaction.created", after_commit: true)
        after_commit { SendWebhookJob.perform_later("wallet_transaction.created", wallet_transaction) }
      end
      invoice.save! if invoice.changed?
      result
    end

    private

    attr_accessor :invoice, :wallets, :customer
    delegate :customer, to: :invoice

    def fee_amount(fee)
      fee.sub_total_excluding_taxes_amount_cents +
        fee.taxes_precise_amount_cents -
        fee.precise_credit_notes_amount_cents
    end

    def wallets_already_applied?
      return false unless invoice

      invoice.wallet_transactions.exists?(wallet_id: wallets.pluck(:id))
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
  end
end
