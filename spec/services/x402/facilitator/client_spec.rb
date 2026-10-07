# frozen_string_literal: true

require "rails_helper"

describe X402::Facilitator::Client do
  describe ".for" do
    subject(:client) { described_class.for(connection) }

    let(:connection) { build(:x402_connection) }

    context "with a Coinbase CDP connection" do
      before { allow(X402::Facilitator::CoinbaseCdpAdapter).to receive(:new).and_call_original }

      it "returns a Coinbase CDP adapter built from the connection credentials" do
        expect(client).to be_a(X402::Facilitator::CoinbaseCdpAdapter)
        expect(X402::Facilitator::CoinbaseCdpAdapter).to have_received(:new).with(api_key_id: "test-key-id", api_key_secret: "test-key-secret")
      end
    end

    context "with a facilitator Lago does not know" do
      let(:connection) { build(:x402_connection, facilitator: "other") }

      it "raises NotImplementedError" do
        expect { client }.to raise_error(NotImplementedError, 'x402 facilitator "other" is not supported')
      end
    end
  end
end
