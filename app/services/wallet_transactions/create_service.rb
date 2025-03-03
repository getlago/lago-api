# frozen_string_literal: true

module WalletTransactions
  class CreateService < BaseService
    Result = BaseResult[:wallet_transaction]

    def initialize(wallet:, credit_amount:, status:, transaction_type:, from_source: :manual, metadata: [], transaction_status: :purchased, invoice_requires_successful_payment: false, settled_at: nil, credit_note_id: nil)
      @wallet = wallet
      @credit_amount = credit_amount
      @status = status
      @transaction_type = transaction_type
      @from_source = from_source
      @transaction_status = transaction_status
      @invoice_requires_successful_payment = invoice_requires_successful_payment
      @metadata = metadata
      @settled_at = settled_at
      @credit_note_id = credit_note_id
      super
    end

    def call
      currency = wallet.currency_for_balance
      result.wallet_transaction = wallet.wallet_transactions.create!(
        amount: (wallet.rate_amount * credit_amount).round(currency.exponent),
        credit_amount:,
        status:,
        transaction_type:,
        source: from_source,
        transaction_status:,
        invoice_requires_successful_payment:,
        metadata:,
        settled_at:,
        credit_note_id:
      )
      result
    end

    private

    attr_reader :wallet, :credit_amount, :status, :transaction_type, :from_source, :transaction_status, :invoice_requires_successful_payment, :metadata, :settled_at, :credit_note_id
  end
end
