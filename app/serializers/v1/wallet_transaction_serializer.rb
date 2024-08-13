# frozen_string_literal: true

module V1
  class WalletTransactionSerializer < ModelSerializer
    def serialize
      {
        lago_id: model.id,
        lago_wallet_id: model.wallet_id,
        status: model.status,
        source: model.source,
        transaction_status: model.transaction_status,
        transaction_type: model.transaction_type,
        amount: model.amount,
        credit_amount: model.credit_amount,
        settled_at: model.settled_at&.iso8601,
        created_at: model.created_at.iso8601,
        invoice_requires_successful_payment: model.invoice_requires_successful_payment?,
        metadata: model.metadata
      }
    end
  end
end
