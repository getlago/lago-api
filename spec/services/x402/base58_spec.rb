# frozen_string_literal: true

require "rails_helper"

describe X402::Base58 do
  describe ".decode" do
    subject(:decoded) { described_class.decode(string) }

    %w[
      EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v
      4zMMC9srt5Ri5X14GAgXhaHii3GnPAEERYPJgZJDncDU
      TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA
      ComputeBudget111111111111111111111111111111
    ].each do |key|
      context "with the Solana key #{key}" do
        let(:string) { key }

        it "decodes to 32 bytes" do
          expect(decoded.bytesize).to eq(32)
        end

        it "round-trips" do
          expect(described_class.encode(decoded)).to eq(key)
        end
      end
    end

    context "with leading ones" do
      let(:string) { "1" * 32 }

      it "decodes each to a zero byte" do
        expect(decoded).to eq("\x00".b * 32)
      end
    end

    context "with 44 z" do
      let(:string) { "z" * 44 }

      it "decodes to 33 bytes" do
        expect(decoded.bytesize).to eq(33)
      end
    end

    ["0OIl", "abc0", "abcO", "abcI", "abcl", "eip155:8453", "0x5aaeb6053f3e94c9b9a09f33669435e7ef1beaed", "", nil].each do |input|
      context "with #{input.inspect}" do
        let(:string) { input }

        it { is_expected.to be_nil }
      end
    end
  end

  describe ".encode" do
    subject(:encoded) { described_class.encode(bytes) }

    let(:bytes) { OpenSSL::Random.random_bytes(64) }

    it "round-trips a 64-byte signature" do
      expect(described_class.decode(encoded)).to eq(bytes)
    end

    context "with no bytes" do
      let(:bytes) { "".b }

      it { is_expected.to eq("") }
    end
  end
end
