# frozen_string_literal: true

module V1
  class WalletTransactionConsumptionSerializer < ModelSerializer
    def serialize
      payload = {
        lago_id: model.id,
        lago_inbound_wallet_transaction_id: model.inbound_wallet_transaction_id,
        lago_outbound_wallet_transaction_id: model.outbound_wallet_transaction_id,
        amount_cents: model.consumed_amount_cents,
        created_at: model.created_at.iso8601
      }

      payload.merge!(inbound_wallet_transaction) if include?(:inbound_wallet_transaction)
      payload.merge!(outbound_wallet_transaction) if include?(:outbound_wallet_transaction)

      payload
    end

    private

    def inbound_wallet_transaction
      {
        inbound_wallet_transaction: ::V1::WalletTransactionSerializer.new(
          model.inbound_wallet_transaction
        ).serialize
      }
    end

    def outbound_wallet_transaction
      {
        outbound_wallet_transaction: ::V1::WalletTransactionSerializer.new(
          model.outbound_wallet_transaction
        ).serialize
      }
    end
  end
end
