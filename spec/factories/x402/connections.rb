# frozen_string_literal: true

FactoryBot.define do
  factory :x402_connection, class: "X402::Connection" do
    organization
    sequence(:code) { |n| "coinbase_cdp_#{n}" }
    name { "Coinbase CDP (Base Sepolia)" }
    networks { ["eip155:84532"] }
    payout_addresses { {"evm" => "0x5aAeb6053F3E94C9b9A09f33669435E7Ef1BeAed"} }
    secrets { {cdp_api_key_id: "test-key-id", cdp_api_key_secret: Base64.strict_encode64(Random.bytes(64))}.to_json }
  end
end
