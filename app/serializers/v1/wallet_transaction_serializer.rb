# frozen_string_literal: true

module V1
  class WalletTransactionSerializer < ModelSerializer
    def serialize
      payload = {
        lago_id: model.id,
        lago_wallet_id: model.wallet_id,
        lago_invoice_id: model.invoice_id,
        lago_credit_note_id: model.credit_note_id,
        status: model.status,
        source: model.source,
        transaction_status: model.transaction_status,
        transaction_type: model.transaction_type,
        amount: model.amount,
        credit_amount: model.credit_amount,
        settled_at: model.settled_at&.iso8601,
        failed_at: model.failed_at&.iso8601,
        created_at: model.created_at.iso8601,
        invoice_requires_successful_payment: model.invoice_requires_successful_payment?,
        metadata: model.metadata,
        name: model.name
      }

      payload.merge!(wallet) if include?(:wallet)
      payload
    end

    private

    def wallet
      {
        wallet: ::V1::WalletSerializer.new(model.wallet).serialize
      }
    end
  end
end
