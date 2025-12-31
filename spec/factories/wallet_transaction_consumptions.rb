# frozen_string_literal: true

FactoryBot.define do
  factory :wallet_transaction_consumption do
    organization { inbound_wallet_transaction&.organization || association(:organization) }
    inbound_wallet_transaction do
      association(:wallet_transaction,
        transaction_type: "inbound",
        organization:,
        remaining_amount_cents: 10000)
    end
    outbound_wallet_transaction do
      association(:wallet_transaction,
        transaction_type: "outbound",
        wallet: inbound_wallet_transaction.wallet,
        organization:)
    end
    consumed_amount_cents { 100 }
  end
end
