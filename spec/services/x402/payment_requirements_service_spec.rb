# frozen_string_literal: true

require "rails_helper"

RSpec.describe X402::PaymentRequirementsService do
  subject(:result) { described_class.call(connection:, amount_cents: 100) }

  let(:connection) { build(:x402_connection) }

  it "asks for a top-up on every configured network" do
    expect(result.requirements).to eq([
      {scheme: "exact", network: "eip155:84532", asset: "usdc", pay_to: "0x5aAeb6053F3E94C9b9A09f33669435E7Ef1BeAed", amount_atomic: "1000000", max_timeout_seconds: 60}
    ])
  end
end
