# frozen_string_literal: true

require "rails_helper"

describe X402::Ed25519 do
  describe ".verify?" do
    subject(:verified) { described_class.verify?(public_key:, signature:, message:) }

    let(:vectors) { JSON.parse(Rails.root.join("spec/fixtures/x402/sign_in_with_x/vectors.json").read).fetch("svm") }
    let(:vector) { vectors.first }
    let(:message) { vector.fetch("message") }
    let(:public_key) { X402::Base58.decode(vector.dig("payload", "address")) }
    let(:signature) { X402::Base58.decode(vector.dig("payload", "signature")) }

    it "accepts every ground-truth vector" do
      results = vectors.map do |entry|
        described_class.verify?(
          public_key: X402::Base58.decode(entry.dig("payload", "address")),
          signature: X402::Base58.decode(entry.dig("payload", "signature")),
          message: entry.fetch("message")
        )
      end

      expect(results).to all(be(true))
    end

    context "with a message that has one more character" do
      let(:message) { "#{vector.fetch("message")}!" }

      it { is_expected.to be(false) }
    end

    context "with the signature of another vector" do
      let(:signature) { X402::Base58.decode(vectors.last.dig("payload", "signature")) }

      it { is_expected.to be(false) }
    end

    context "with a 31-byte key" do
      let(:public_key) { X402::Base58.decode(vector.dig("payload", "address")).byteslice(0, 31) }

      it { is_expected.to be(false) }
    end

    context "with a 63-byte signature" do
      let(:signature) { X402::Base58.decode(vector.dig("payload", "signature")).byteslice(0, 63) }

      it { is_expected.to be(false) }
    end

    context "with values that are not strings" do
      let(:public_key) { 5 }
      let(:signature) { nil }

      it { is_expected.to be(false) }
    end

    context "with the small-order forgery" do
      let(:public_key) { "\x01".b + ("\x00" * 31).b }
      let(:signature) { public_key + ("\x00" * 32).b }
      let(:message) { "any" }

      it "is accepted by plain OpenSSL" do
        expect(OpenSSL::PKey.new_raw_public_key("ED25519", public_key).verify(nil, signature, message)).to be(true)
      end

      it { is_expected.to be(false) }
    end

    described_class::SMALL_ORDER_KEYS.each do |hex|
      [false, true].each do |top_bit|
        context "with the small-order key #{hex} #{top_bit ? "with" : "without"} the top bit set" do
          let(:public_key) do
            bytes = [hex].pack("H*")
            bytes.setbyte(31, bytes.getbyte(31) | 0x80) if top_bit
            bytes
          end
          let(:signature) { ("\x00" * 64).b }
          let(:message) { "any" }

          it { is_expected.to be(false) }
        end
      end
    end

    context "with random keys and signatures" do
      it "returns false and never raises" do
        results = Array.new(100) do
          described_class.verify?(public_key: Random.bytes(32), signature: Random.bytes(64), message: "any")
        end

        expect(results).to all(be(false))
      end
    end
  end
end
