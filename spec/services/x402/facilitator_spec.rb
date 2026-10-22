# frozen_string_literal: true

require "rails_helper"

describe X402::Facilitator do
  describe X402::Facilitator::SettleResult do
    subject(:settle_result) { described_class.new(outcome:, transaction: nil, network: nil, payer: nil, error_reason: nil, response: {}) }

    {
      settled: [true, false],
      unconfirmed_failure: [false, true],
      settlement_pending: [false, true],
      server_error: [false, true],
      no_response: [false, true]
    }.each do |settle_outcome, (settled, pending)|
      context "when #{settle_outcome}" do
        let(:outcome) { settle_outcome }

        it "answers its predicates" do
          expect([settle_result.settled?, settle_result.pending?]).to eq([settled, pending])
        end
      end
    end

    context "with an unknown outcome" do
      let(:outcome) { :lost }

      it "raises" do
        expect { settle_result }.to raise_error(ArgumentError, /unknown settle outcome/)
      end
    end
  end

  describe X402::Facilitator::SupportedResult do
    subject(:supported) { described_class.new(kinds: JSON.parse(File.read(Rails.root.join("spec/fixtures/x402/cdp/supported.json")))["kinds"], response: {}) }

    it "supports a listed network" do
      expect(supported.supports?(network: "eip155:84532")).to be(true)
    end

    it "does not support an unlisted network" do
      expect(supported.supports?(network: "eip155:1")).to be(false)
    end

    it "matches the x402 version" do
      expect(supported.supports?(network: "base-sepolia", x402_version: 2)).to be(false)
    end

    it "reads Solana's fee payer" do
      expect(supported.fee_payer(network: "solana:EtWTRABZaYq6iMfeYKouRu166VU2xqa1")).to eq("GVJJ7rdGiXr5xaYbRwRbjfaJL7fmwRygFi1H6aGqDveb")
    end

    it "has no fee payer on an unlisted network" do
      expect(supported.fee_payer(network: "solana:5eykt4UsFv8P8NJdTREpY1vzqKqZKvdp")).to be_nil
    end

    it "has no fee payer on EVM" do
      expect(supported.fee_payer(network: "eip155:84532")).to be_nil
    end

    context "with another scheme listed first for the network" do
      subject(:supported) do
        described_class.new(response: {}, kinds: [
          {"x402Version" => 2, "scheme" => "upto", "network" => "solana:EtWTRABZaYq6iMfeYKouRu166VU2xqa1", "extra" => {"feePayer" => "HHU1aLQQCbCzW9ebjFTntq2vkvsQsxkDyPjMsW2WtiLG"}},
          {"x402Version" => 2, "scheme" => "exact", "network" => "solana:EtWTRABZaYq6iMfeYKouRu166VU2xqa1", "extra" => {"feePayer" => "GVJJ7rdGiXr5xaYbRwRbjfaJL7fmwRygFi1H6aGqDveb"}}
        ])
      end

      it "reads the exact v2 kind's fee payer" do
        expect(supported.fee_payer(network: "solana:EtWTRABZaYq6iMfeYKouRu166VU2xqa1")).to eq("GVJJ7rdGiXr5xaYbRwRbjfaJL7fmwRygFi1H6aGqDveb")
      end
    end
  end

  describe X402::Facilitator::Error do
    subject(:error) { X402::Facilitator::CredentialError.new("verify: HTTP 401", http_status: 401, error_type: nil, correlation_id: "corr-1") }

    it "carries what CDP said" do
      expect(error).to have_attributes(message: "verify: HTTP 401", http_status: 401, correlation_id: "corr-1")
    end
  end
end
