# frozen_string_literal: true

require "rails_helper"

RSpec.describe X402::Facilitator::CoinbaseCdpAdapter do
  subject(:adapter) { described_class.new(connection:) }

  include_context "with an x402 payment"

  let(:organization) { create(:organization) }

  describe "#verify" do
    it "forwards the payment unchanged and returns the facilitator's verdict" do
      expect(adapter.verify(payment:, payment_requirements:)).to have_attributes(valid: true, payer: agent_address)
      expect(
        a_request(:post, verify_url)
          .with(body: {x402Version: 2, paymentPayload: payment, paymentRequirements: payment_requirements}, headers: {"Authorization" => /\ABearer \S+\z/})
      ).to have_been_made.once
    end
  end

  describe "#settle" do
    it "returns a settled result carrying the transaction hash" do
      expect(adapter.settle(payment:, payment_requirements:)).to have_attributes(status: :settled, transaction: settle_tx_hash, network: "eip155:84532")
    end
  end
end
