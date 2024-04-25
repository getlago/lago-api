# frozen_string_literal: true

module Credits
  class AppliedPrepaidCreditService < BaseService
    def initialize(invoice:, wallet:)
      @invoice = invoice
      @wallet = wallet

      super(nil)
    end

    def call
      return result if already_applied?

      amount_cents = compute_amount
      amount = compute_amount_from_cents(amount_cents)
      credit_amount = amount.fdiv(wallet.rate_amount)

      ActiveRecord::Base.transaction do
        wallet_transaction = WalletTransaction.create!(
          invoice:,
          wallet:,
          transaction_type: :outbound,
          amount:,
          credit_amount:,
          status: :settled,
          settled_at: Time.current,
          transaction_status: :purchased,
        )

        result.wallet_transaction = wallet_transaction
        Wallets::Balance::DecreaseService.new(wallet:, credits_amount: credit_amount).call

        result.prepaid_credit_amount_cents = amount_cents
        invoice.prepaid_credit_amount_cents += amount_cents
      end

      SendWebhookJob.perform_later('wallet_transaction.created', result.wallet_transaction)

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
      return balance_cents if balance_cents <= invoice.total_amount_cents

      invoice.total_amount_cents
    end

    def compute_amount_from_cents(amount)
      currency = invoice.total_amount.currency

      amount.round.fdiv(currency.subunit_to_unit)
    end
  end
end
