# frozen_string_literal: true

module WalletTransactions
  class CreateService < BaseService
    Result = BaseResult[:wallet_transaction]

    def initialize(wallet:, credit_amount:, status:, transaction_type:, source: :manual, metadata: [], transaction_status: :purchased, invoice_requires_successful_payment: false, settled_at: nil)
      @wallet = wallet
      @credit_amount = credit_amount
      @status = status
      @transaction_type = transaction_type
      @source = source
      @transaction_status = transaction_status
      @invoice_requires_successful_payment = invoice_requires_successful_payment
      @metadata = metadata
      @settled_at = settled_at
      super
    end

    def call
      currency = wallet.currency_for_balance
      result.wallet_transaction = wallet.wallet_transactions.create!(
        amount: (wallet.rate_amount * credit_amount).round(currency.exponent),
        credit_amount:,
        status:,
        transaction_type:,
        source:,
        transaction_status:,
        invoice_requires_successful_payment:,
        metadata:,
        settled_at:
      )
      result
    end

    private

    attr_reader :wallet, :credit_amount, :status, :transaction_type, :source, :transaction_status, :invoice_requires_successful_payment, :metadata
  end
end
