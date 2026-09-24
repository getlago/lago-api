# frozen_string_literal: true

require "rails_helper"

RSpec.describe X402::Network do
  describe ".checksum" do
    subject(:checksum) { described_class.checksum(address) }

    let(:address) { "0x5aaeb6053f3e94c9b9a09f33669435e7ef1beaed" }

    it "returns the EIP-55 form" do
      expect(checksum).to eq("0x5aAeb6053F3E94C9b9A09f33669435E7Ef1BeAed")
    end

    context "with an upper-case address" do
      let(:address) { "0xFB6916095CA1DF60BB79CE92CE3EA74C37C5D359" }

      it "returns the EIP-55 form" do
        expect(checksum).to eq("0xfB6916095ca1df60bB79Ce92cE3Ea74c37c5d359")
      end
    end
  end

  describe ".family_of_network" do
    subject(:family) { described_class.family_of_network(network) }

    let(:network) { "eip155:84532" }

    it { is_expected.to eq(:evm) }

    context "with a Solana network" do
      let(:network) { "solana:EtWTRABZaYq6iMfeYKouRu166VU2xqa1" }

      it { is_expected.to eq(:svm) }
    end
  end
end
