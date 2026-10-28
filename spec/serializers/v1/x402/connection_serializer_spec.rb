# frozen_string_literal: true

require "rails_helper"

describe V1::X402::ConnectionSerializer do
  subject(:serializer) { described_class.new(connection, root_name: "x402_connection") }

  let(:connection) { create(:x402_connection, networks: ["eip155:84532", "solana:EtWTRABZaYq6iMfeYKouRu166VU2xqa1"], payout_addresses:, allowed_origins:) }
  let(:allowed_origins) { ["https://api.example.com", "http://localhost:3000"] }
  let(:payout_addresses) do
    {"evm" => "0x5aAeb6053F3E94C9b9A09f33669435E7Ef1BeAed", "svm" => "2wKupLR9q6wXYppw8Gr2NvWxKBUqm4PPJKkQfoxHDBg4"}
  end
  let(:result) { JSON.parse(serializer.to_json)["x402_connection"] }

  it "serializes the connection" do
    expect(result).to eq(
      "lago_id" => connection.id,
      "lago_organization_id" => connection.organization_id,
      "code" => connection.code,
      "name" => connection.name,
      "facilitator" => "coinbase_cdp",
      "asset" => "usdc",
      "networks" => ["eip155:84532", "solana:EtWTRABZaYq6iMfeYKouRu166VU2xqa1"],
      "payout_addresses" => payout_addresses,
      "auto_create_customers" => true,
      "allowed_origins" => allowed_origins,
      "created_at" => connection.created_at.iso8601,
      "updated_at" => connection.updated_at.iso8601
    )
  end

  it "renders no secret" do
    expect(result.keys.grep(/secret|cdp_api_key/)).to be_empty
  end
end
