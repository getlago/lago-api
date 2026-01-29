# frozen_string_literal: true

module Credits
  class AppliedPrepaidCreditsService < BaseService
    DEFAULT_MAX_WALLET_DECREASE_ATTEMPTS = 6

    def initialize(invoice:, max_wallet_decrease_attempts: DEFAULT_MAX_WALLET_DECREASE_ATTEMPTS)
      @invoice = invoice
      @max_wallet_decrease_attempts = max_wallet_decrease_attempts
      raise ArgumentError, "max_wallet_decrease_attempts must be between 1 and #{DEFAULT_MAX_WALLET_DECREASE_ATTEMPTS} (inclusive)" if max_wallet_decrease_attempts < 1 || max_wallet_decrease_attempts > DEFAULT_MAX_WALLET_DECREASE_ATTEMPTS

      super(nil)
    end

    def call
      if wallets_already_applied?
        return result.service_failure!(code: "already_applied", message: "Prepaid credits already applied")
      end

      result.prepaid_credit_amount_cents ||= 0
      result.wallet_transactions ||= []

      return result if wallets.empty?

      ActiveRecord::Base.transaction do
        ordered_remaining_amounts = calculate_amounts_for_fees_by_type_and_bm
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

            next unless applicable_fee?(fee_key:, targets: wallet_targets_array, types: wallet_types_array)

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

          wallet_transaction = create_wallet_transaction(wallet, total_amount_cents)
          amount_cents = wallet_transaction.amount_cents

          if wallet.traceable?
            WalletTransactions::TrackConsumptionService.call!(outbound_wallet_transaction: wallet_transaction)
          end

          with_optimistic_lock_retry(wallet) do
            Wallets::Balance::DecreaseService.call(wallet:, wallet_transaction:, skip_refresh: true)
          end

          result.wallet_transactions << wallet_transaction
          result.prepaid_credit_amount_cents += amount_cents
          invoice.prepaid_credit_amount_cents += amount_cents
        end

        Customers::RefreshWalletsService.call(customer:, include_generating_invoices: true)
        invoice.save! if invoice.changed?
      end

      schedule_webhook_notifications(result.wallet_transactions)
      result
    rescue ActiveRecord::RecordInvalid => e
      result.record_validation_failure!(record: e.record)
    end

    private

    attr_accessor :invoice, :max_wallet_decrease_attempts

    delegate :customer, to: :invoice

    def schedule_webhook_notifications(wallet_transactions)
      wallet_transactions.each do |wt|
        Utils::ActivityLog.produce_after_commit(wt, "wallet_transaction.created")
        SendWebhookJob.perform_after_commit("wallet_transaction.created", wt)
      end
    end

    def calculate_amounts_for_fees_by_type_and_bm
      invoice_cap = invoice.total_amount_cents
      remaining = Hash.new(0)

      invoice.fees.includes(:charge).find_each do |fee|
        next if fee.sub_total_excluding_taxes_amount_cents == 0

        cap = fee.sub_total_excluding_taxes_amount_cents +
          fee.taxes_precise_amount_cents -
          fee.precise_credit_notes_amount_cents

        cap = [cap, invoice_cap].min

        next if cap <= 0
        key = [fee.fee_type, fee.charge&.billable_metric_id]
        remaining[key] += cap
        invoice_cap -= cap
      end

      remaining.sort_by { |_, v| -v }.to_h
    end

    def wallets_already_applied?
      return false unless invoice

      WalletTransaction.exists?(invoice_id: invoice.id, wallet_id: wallets.map(&:id))
    end

    def create_wallet_transaction(wallet, amount_cents)
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

    def applicable_fee?(fee_key:, targets:, types:)
      target_match = targets.include?(fee_key)
      type_match = types.include?(fee_key.first)
      unrestricted_wallet = targets.empty? && types.empty?

      target_match || type_match || unrestricted_wallet
    end

    def wallets
      @wallets ||= customer.wallets.active.includes(:wallet_targets).with_positive_balance.in_application_order
    end
  end
end
