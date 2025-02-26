# frozen_string_literal: true

module WalletTransactions
  class CreateService < BaseService
    Result = BaseResult[:wallet_transaction]

    def initialize(wallet:, wallet_credit:, status:, transaction_type:, from_source: :manual, metadata: [], transaction_status: :purchased, invoice_requires_successful_payment: false, settled_at: nil, credit_note_id: nil, invoice_id: nil)
      @wallet = wallet
      @wallet_credit = wallet_credit
      @status = status
      @transaction_type = transaction_type
      @from_source = from_source
      @transaction_status = transaction_status
      @invoice_requires_successful_payment = invoice_requires_successful_payment
      @metadata = metadata
      @settled_at = settled_at
      @credit_note_id = credit_note_id
      @invoice_id = invoice_id
      super
    end

    def call
      result.wallet_transaction = wallet.wallet_transactions.create!(
        amount:,
        status:,
        credit_amount:,
        transaction_type:,
        source: from_source,
        transaction_status:,
        invoice_requires_successful_payment:,
        metadata:,
        settled_at:,
        credit_note_id:,
        invoice_id:
      )
      result
    end

    private

    delegate :credit_amount, :amount, to: :wallet_credit

    attr_reader :wallet, :wallet_credit, :status, :transaction_type, :from_source, :transaction_status, :invoice_requires_successful_payment, :metadata, :settled_at, :credit_note_id, :invoice_id
  end
end
