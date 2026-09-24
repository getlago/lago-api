# frozen_string_literal: true

module V1
  module X402
    class SettlementSerializer < ModelSerializer
      def serialize
        {
          lago_id: model.id,
          status: model.status,
          replayed: false,
          network: model.network,
          transaction_hash: model.transaction_hash,
          payer_address: model.payer_address,
          lago_customer_id: model.customer_id,
          lago_wallet_transaction_id: model.wallet_transaction_id,
          external_subscription_id: model.subscription&.external_id,
          credits_granted: model.wallet_transaction&.credit_amount&.to_s,
          settled_amount_cents: model.settled_amount_cents,
          reconcile_after: model.pending? ? model.reconcile_after&.iso8601 : nil
        }
      end
    end
  end
end
