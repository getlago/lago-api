# frozen_string_literal: true

require "rails_helper"

RSpec.describe X402::Asset do
  subject(:asset) { described_class.fetch(code: "usdc", network: "eip155:84532") }

  it "describes USDC on Base Sepolia" do
    expect(asset).to have_attributes(address: "0x036CbD53842c5426634e7929541eC2318f3dCF7e", decimals: 6, eip712_name: "USDC", eip712_version: "2", atomic_units_per_cent: 10_000)
  end
end
