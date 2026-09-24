# frozen_string_literal: true

FactoryBot.define do
  factory :x402_settlement, class: "X402::Settlement" do
    organization
    x402_connection { association(:x402_connection, organization:) }
    kind { "credit_purchase" }
    status { "settled" }
    network { "eip155:84532" }
    asset { "0x036CbD53842c5426634e7929541eC2318f3dCF7e" }
    payer_address { "0xfB6916095ca1df60bB79Ce92cE3Ea74c37c5d359" }
    payee_address { "0x5aAeb6053F3E94C9b9A09f33669435E7Ef1BeAed" }
    settled_amount_atomic { 1_000_000 }
    settled_amount_cents { 100 }
    transaction_hash { "0x#{SecureRandom.hex(32)}" }
    payment_digest { SecureRandom.hex(32) }
    purchase_settings { {"plan_code" => "agent_api", "wallet_code" => "agent_credits", "wallet" => {"name" => "Agent credits", "rate_amount" => "0.01", "currency" => "USD"}} }
  end
end
