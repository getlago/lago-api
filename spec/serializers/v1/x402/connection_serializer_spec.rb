# frozen_string_literal: true

require "rails_helper"

describe V1::X402::ConnectionSerializer do
  subject(:serializer) { described_class.new(connection, root_name: "x402_connection") }

  let(:connection) { create(:x402_connection, networks: ["eip155:84532", "solana:EtWTRABZaYq6iMfeYKouRu166VU2xqa1"], payout_addresses:) }
  let(:payout_addresses) do
    {"evm" => "0x5aAeb6053F3E94C9b9A09f33669435E7Ef1BeAed", "svm" => "2wKupLR9q6wXYppw8Gr2NvWxKBUqm4PPJKkQfoxHDBg4"}
  end
  let(:result) { JSON.parse(serializer.to_json)["x402_connection"] }

  it "serializes exactly the documented keys" do
    expect(result.keys).to match_array(
      %w[lago_id lago_organization_id code name facilitator asset networks payout_addresses auto_create_customers created_at updated_at]
    )
  end

  it "serializes the connection" do
    expect(result).to include(
      "lago_id" => connection.id,
      "lago_organization_id" => connection.organization_id,
      "code" => connection.code,
      "name" => connection.name,
      "facilitator" => "coinbase_cdp",
      "asset" => "usdc",
      "auto_create_customers" => true,
      "created_at" => connection.created_at.iso8601,
      "updated_at" => connection.updated_at.iso8601
    )
  end

  it "renders networks and payout addresses as stored" do
    expect(result).to include("networks" => connection.networks, "payout_addresses" => payout_addresses)
  end

  it "renders no secret" do
    expect(result.keys.grep(/secret|cdp_api_key/)).to be_empty
  end
end
