# frozen_string_literal: true

module Credits
  class AppliedPrepaidCreditService < BaseService
    def initialize(invoice:, wallet:)
      @invoice = invoice
      @wallet = wallet

      super(nil)
    end

    def create
      return result if already_applied?

      amount_cents = compute_amount
      amount = compute_amount_from_cents(amount_cents)
      credit_amount = amount.fdiv(wallet.rate_amount)

      ActiveRecord::Base.transaction do
        wallet_transaction = WalletTransaction.create!(
          invoice: invoice,
          wallet: wallet,
          transaction_type: :outbound,
          amount: amount,
          credit_amount: credit_amount,
          status: :settled,
          settled_at: Time.current,
        )

        result.wallet_transaction = wallet_transaction

        Wallets::Balance::DecreaseService.new(wallet: wallet, credits_amount: credit_amount).call

        result.prepaid_credit_amount_cents = amount_cents
      end

      result
    rescue ActiveRecord::RecordInvalid => e
      result.record_validation_failure!(record: e.record)
    end

    private

    attr_accessor :invoice, :wallet

    def already_applied?
      invoice&.wallet_transactions&.exists?
    end

    def compute_amount
      return balance_cents if balance_cents <= invoice.total_amount_cents

      invoice.total_amount_cents
    end

    def compute_amount_from_cents(amount)
      currency = invoice.amount.currency

      amount.round.fdiv(currency.subunit_to_unit)
    end

    def balance_cents
      balance = wallet.balance
      currency = invoice.amount.currency
      rounded_amount = balance.round(currency.exponent)

      rounded_amount * currency.subunit_to_unit
    end
  end
end
