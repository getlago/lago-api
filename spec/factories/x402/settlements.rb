# frozen_string_literal: true

FactoryBot.define do
  factory :x402_settlement, class: "X402::Settlement" do
    x402_connection
    organization { x402_connection&.organization || association(:organization) }
    kind { "credit_purchase" }
    status { "settled" }
    network { "eip155:84532" }
    asset { "0x036CbD53842c5426634e7929541eC2318f3dCF7e" }
    payer_address { "0x#{SecureRandom.hex(20)}" }
    payee_address { "0x5aAeb6053F3E94C9b9A09f33669435E7Ef1BeAed" }
    settled_amount_atomic { 1_000_000 }
    settled_amount_cents { 100 }
    transaction_hash { "0x#{SecureRandom.hex(32)}" }
    payment_digest { SecureRandom.hex(32) }
    purchase_settings { {"plan_code" => "agent_api", "wallet_code" => "agent_credits"} }

    trait :pending do
      status { "pending" }
      transaction_hash { nil }
      reconcile_after { 5.minutes.from_now }
    end

    trait :failed do
      status { "failed" }
      transaction_hash { nil }
      error_reason { "invalid_exact_evm_payload_signature" }
    end

    trait :invoice_payment do
      kind { "invoice_payment" }
      invoice { association(:invoice, organization:) }
      purchase_settings { nil }
    end

    trait :merchant do
      settled_by { "merchant" }
    end

    trait :solana do
      network { "solana:EtWTRABZaYq6iMfeYKouRu166VU2xqa1" }
      asset { "4zMMC9srt5Ri5X14GAgXhaHii3GnPAEERYPJgZJDncDU" }
      payer_address { "2wKupLR9q6wXYppw8Gr2NvWxKBUqm4PPJKkQfoxHDBg4" }
      payee_address { "TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA" }
      transaction_hash { X402::Base58.encode(SecureRandom.random_bytes(64)) }
    end
  end
end
