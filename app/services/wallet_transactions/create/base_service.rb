# frozen_string_literal: true

module WalletTransactions
  module Create
    class BaseService < ::BaseService
      Result = BaseResult[:wallet_transaction]

      def initialize(wallet:, status:, transaction_type:, from_source: :manual, metadata: [], transaction_status: :purchased, invoice_requires_successful_payment: false, settled_at: nil, credit_note_id: nil, invoice_id: nil)
        @wallet = wallet
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

      attr_reader :wallet, :credit_amount, :status, :transaction_type, :from_source, :transaction_status, :invoice_requires_successful_payment, :metadata, :settled_at, :credit_note_id, :invoice_id, :amount
    end
  end
end
