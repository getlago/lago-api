# frozen_string_literal: true

module Credits
  class AppliedPrepaidCreditService < BaseService
    def initialize(invoice:, wallet:)
      @invoice = invoice
      @wallet = wallet

      super(nil)
    end

    def call
      if already_applied?
        return result.service_failure!(code: "already_applied", message: "Prepaid credits already applied")
      end

      amount_cents = compute_amount
      wallet_credit = WalletCredit.from_amount_cents(wallet:, amount_cents:)

      ActiveRecord::Base.transaction do
        wallet_transaction = WalletTransactions::CreateService.call!(
          wallet:,
          wallet_credit:,
          invoice_id: invoice.id,
          transaction_type: :outbound,
          status: :settled,
          settled_at: Time.current,
          transaction_status: :invoiced
        ).wallet_transaction

        result.wallet_transaction = wallet_transaction
        Wallets::Balance::DecreaseService.new(wallet:, wallet_transaction: wallet_transaction).call

        result.prepaid_credit_amount_cents = amount_cents
        invoice.prepaid_credit_amount_cents += amount_cents
      end

      after_commit { SendWebhookJob.perform_later("wallet_transaction.created", result.wallet_transaction) }

      result
    rescue ActiveRecord::RecordInvalid => e
      result.record_validation_failure!(record: e.record)
    end

    private

    attr_accessor :invoice, :wallet

    delegate :balance_cents, to: :wallet

    def already_applied?
      invoice&.wallet_transactions&.exists?
    end

    def compute_amount
      [balance_cents, invoice.total_amount_cents].min
    end
  end
end
