# frozen_string_literal: true

require "rails_helper"

describe X402::Asset do
  subject(:asset) { described_class.fetch(code: "usdc", network:) }

  let(:network) { "eip155:84532" }

  describe ".fetch" do
    {
      "eip155:8453" => ["0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913", {"name" => "USD Coin", "version" => "2"}],
      "eip155:84532" => ["0x036CbD53842c5426634e7929541eC2318f3dCF7e", {"name" => "USDC", "version" => "2"}],
      "solana:5eykt4UsFv8P8NJdTREpY1vzqKqZKvdp" => ["EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v", nil],
      "solana:EtWTRABZaYq6iMfeYKouRu166VU2xqa1" => ["4zMMC9srt5Ri5X14GAgXhaHii3GnPAEERYPJgZJDncDU", nil]
    }.each do |usdc_network, (address, domain)|
      context "with USDC on #{usdc_network}" do
        let(:network) { usdc_network }

        it "describes the token" do
          expect(asset).to have_attributes(address:, decimals: 6, eip712_domain: domain)
        end
      end
    end

    it "raises on an asset Lago does not accept" do
      expect { described_class.fetch(code: "usdc", network: "eip155:1") }.to raise_error(KeyError)
    end
  end

  describe "DEFINITIONS" do
    it "covers exactly the networks Lago accepts" do
      expect(described_class::DEFINITIONS.values.map(&:network).uniq).to match_array(X402::Network::NETWORKS.keys)
    end
  end

  describe "#atomic_units_per_cent" do
    it "is 10_000 for a 6-decimal asset" do
      expect(asset.atomic_units_per_cent).to eq(10_000)
    end

    context "with a 7-decimal asset" do
      subject(:asset) { described_class.new(code: "usdc", network: "stellar:pubnet", address: "USDC", decimals: 7, eip712_name: nil, eip712_version: nil) }

      it "is 100_000" do
        expect(asset.atomic_units_per_cent).to eq(100_000)
      end
    end
  end

  describe "#cents_from_atomic" do
    it "floors away the sub-cent dust" do
      expect(asset.cents_from_atomic(10_000_015)).to eq(1000)
    end
  end

  describe "strict parsing" do
    it "reads a leading zero as decimal" do
      expect(asset.cents_from_atomic("010000")).to eq(1)
    end

    it "refuses what Integer() would misread" do
      expect { asset.cents_from_atomic("0x10000") }.to raise_error(ArgumentError, /not an unsigned integer/)
    end

    it "refuses a fraction of a cent" do
      expect { asset.atomic_from_cents(1.9) }.to raise_error(ArgumentError, /not an unsigned integer/)
    end
  end

  describe "#atomic_from_cents" do
    it "scales cents to the asset's units" do
      expect(asset.atomic_from_cents(1000)).to eq(10_000_000)
    end
  end
end
