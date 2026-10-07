# frozen_string_literal: true

FactoryBot.define do
  factory :x402_connection, class: "X402::Connection" do
    organization
    sequence(:code) { |n| "coinbase_cdp_#{n}" }
    name { "Coinbase CDP" }
    networks { ["eip155:84532"] }
    payout_addresses { {"evm" => "0x5aAeb6053F3E94C9b9A09f33669435E7Ef1BeAed"} }
    cdp_api_key_id { "test-key-id" }
    cdp_api_key_secret { "test-key-secret" }

    trait :discarded do
      deleted_at { Time.current }
    end

    trait :solana do
      networks { ["solana:EtWTRABZaYq6iMfeYKouRu166VU2xqa1"] }
      payout_addresses { {"svm" => "2wKupLR9q6wXYppw8Gr2NvWxKBUqm4PPJKkQfoxHDBg4"} }
    end
  end
end
