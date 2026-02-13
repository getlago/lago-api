# frozen_string_literal: true

module Credits
  class AppliedPrepaidCreditsService < BaseService
    def initialize(invoice:)
      @invoice = invoice

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
        Customers::LockService.call(customer:, scope: :prepaid_credit) do
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

            wallet_transaction = create_wallet_transaction(wallet, total_amount_cents)

            if wallet.traceable?
              WalletTransactions::TrackConsumptionService.call!(outbound_wallet_transaction: wallet_transaction)
            end

            Wallets::Balance::DecreaseService.call(wallet:, wallet_transaction:, skip_refresh: true)

            result.wallet_transactions << wallet_transaction
          end

          update_prepaid_credit_amounts(result.wallet_transactions)
          Customers::RefreshWalletsService.call(customer:, include_generating_invoices: true)
          invoice.save! if invoice.changed?
        end
      end

      schedule_webhook_notifications(result.wallet_transactions)
      result
    rescue ActiveRecord::RecordInvalid => e
      result.record_validation_failure!(record: e.record)
    end

    private

    attr_accessor :invoice

    delegate :customer, to: :invoice

    def schedule_webhook_notifications(wallet_transactions)
      wallet_transactions.each do |wt|
        Utils::ActivityLog.produce_after_commit(wt, "wallet_transaction.created")
        SendWebhookJob.perform_after_commit("wallet_transaction.created", wt)
      end
    end

    def update_prepaid_credit_amounts(wallet_transactions)
      return if wallet_transactions.empty?

      total_amount = wallet_transactions.sum(&:amount_cents)
      result.prepaid_credit_amount_cents += total_amount
      invoice.prepaid_credit_amount_cents += total_amount

      calculate_prepaid_credit_breakdown(wallet_transactions)
    end

    def calculate_prepaid_credit_breakdown(wallet_transactions)
      return unless invoice.customer.wallets.all?(&:traceable?)

      granted_amount = 0
      purchased_amount = 0

      consumptions = WalletTransactionConsumption
        .where(outbound_wallet_transaction_id: wallet_transactions.map(&:id))
        .includes(:inbound_wallet_transaction)

      consumptions.each do |consumption|
        if consumption.inbound_wallet_transaction.granted?
          granted_amount += consumption.consumed_amount_cents
        else
          purchased_amount += consumption.consumed_amount_cents
        end
      end

      invoice.prepaid_granted_credit_amount_cents = granted_amount if granted_amount > 0
      invoice.prepaid_purchased_credit_amount_cents = purchased_amount if purchased_amount > 0
    end

    def calculate_amounts_for_fees_by_type_and_bm
      remaining = Hash.new(0)

      invoice.fees.includes(:charge).find_each do |fee|
        next if fee.sub_total_excluding_taxes_amount_cents == 0

        cap = fee.sub_total_excluding_taxes_amount_cents +
          fee.taxes_precise_amount_cents -
          fee.precise_credit_notes_amount_cents

        next if cap <= 0
        key = [fee.fee_type, fee.charge&.billable_metric_id]
        if fee.organization.events_targeting_wallets_enabled? && fee.charge&.accepts_target_wallet
          key << fee.grouped_by&.dig("target_wallet_code")
        end
        remaining[key] += cap
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
      @wallets ||= customer.wallets.active.includes(:wallet_targets).with_positive_balance.in_application_order
    end
  end
end
