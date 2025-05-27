# frozen_string_literal: true

module Credits
  class AppliedPrepaidCreditService < BaseService
    MAX_WALLET_DECREASE_ATTEMPTS = 5

    def initialize(invoice:, wallet:)
      @invoice = invoice
      @wallet = wallet

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
      wallet_credit = WalletCredit.from_amount_cents(wallet:, amount_cents:)
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

      decrease_attempt = 0
      begin
        decrease_attempt += 1
        Wallets::Balance::DecreaseService.new(wallet:, wallet_transaction: wallet_transaction).call
      rescue ActiveRecord::StaleObjectError
        if decrease_attempt <= MAX_WALLET_DECREASE_ATTEMPTS
          sleep(rand(0.1..0.5))
          wallet.reload # Make sure the wallet is reloaded before retrying
          retry
        end

        raise
      end

      result.prepaid_credit_amount_cents = amount_cents
      invoice.prepaid_credit_amount_cents += amount_cents

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
