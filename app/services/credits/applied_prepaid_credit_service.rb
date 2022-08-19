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
      credit_amount = amount.fdiv(BigDecimal(wallet.rate_amount))

      wallet_transaction = WalletTransaction.create!(
        wallet: wallet,
        transaction_type: :outbound,
        amount: amount,
        credit_amount: credit_amount,
        status: :settled,
        settled_at: Time.zone.now,
      )

      new_credit = AppliedPrepaidCredit.create!(
        invoice: invoice,
        wallet_transaction: wallet_transaction,
        amount_cents: amount_cents,
        amount_currency: wallet.customer.default_currency,
      )

      Wallets::Balance::DecreaseService.new(wallet: wallet, credits_amount: credit_amount).call

      result.prepaid_credit = new_credit
      result
    rescue ActiveRecord::RecordInvalid => e
      result.fail_with_validations!(e.record)
    end

    private

    attr_accessor :invoice, :wallet

    def already_applied?
      invoice&.applied_prepaid_credits&.exists?
    end

    def compute_amount
      return balance_cents if balance_cents <= invoice.amount_cents

      invoice.amount_cents
    end

    def compute_amount_from_cents(amount)
      currency = invoice.amount.currency

      amount.round.fdiv(currency.subunit_to_unit)
    end

    def balance_cents
      balance = BigDecimal(wallet.balance)
      currency = invoice.amount.currency
      rounded_amount = balance.round(currency.exponent)

      rounded_amount * currency.subunit_to_unit
    end
  end
end
