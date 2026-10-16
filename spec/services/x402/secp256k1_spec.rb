# frozen_string_literal: true

require "rails_helper"

describe X402::Secp256k1 do
  describe ".recover_public_key" do
    subject(:public_key) { described_class.recover_public_key(digest:, signature:) }

    let(:order) { OpenSSL::PKey::EC::Group.new("secp256k1").order }
    let(:vector) { evm_vectors.first }
    let(:digest) { eip191_digest(vector["message"]) }
    let(:vector_signature) { [vector["payload"]["signature"].delete_prefix("0x")].pack("H*") }
    let(:signature) { vector_signature }
    let(:r) { vector_signature.byteslice(0, 32) }
    let(:s) { vector_signature.byteslice(32, 32) }
    let(:v) { vector_signature.getbyte(64) }

    def evm_vectors = JSON.parse(Rails.root.join("spec/fixtures/x402/sign_in_with_x/vectors.json").read)["evm"]
    def eip191_digest(message) = X402::Keccak256.digest("\x19Ethereum Signed Message:\n#{message.bytesize}#{message}")

    JSON.parse(Rails.root.join("spec/fixtures/x402/sign_in_with_x/vectors.json").read)["evm"].each_with_index do |entry, index|
      context "with the #{entry["name"]} vector" do
        let(:vector) { evm_vectors[index] }

        it("recovers viem's public key") { expect("0x#{public_key.unpack1("H*")}").to eq(vector["public_key"]) }
      end
    end

    context "with v written as 0 or 1" do
      let(:signature) { r + s + (v - 27).chr }

      it { expect("0x#{public_key.unpack1("H*")}").to eq(vector["public_key"]) }
    end

    context "with another digest" do
      let(:digest) { eip191_digest("#{vector["message"]}.") }

      it { expect("0x#{public_key.unpack1("H*")}").not_to eq(vector["public_key"]) }
    end

    {
      "v of 29" => ->(r, s, _v, _n) { r + s + 29.chr },
      "a zero r" => ->(_r, s, v, _n) { ("\x00" * 32).b + s + v.chr },
      "a zero s" => ->(r, _s, v, _n) { r + ("\x00" * 32).b + v.chr },
      "r equal to the order" => ->(_r, s, v, n) { [n.to_s(16).rjust(64, "0")].pack("H*") + s + v.chr },
      "s equal to the order" => ->(r, _s, v, n) { r + [n.to_s(16).rjust(64, "0")].pack("H*") + v.chr },
      "r above the order" => ->(_r, s, v, n) { [(n + 2).to_s(16).rjust(64, "0")].pack("H*") + s + v.chr },
      "an r off the curve" => ->(_r, s, v, _n) { [5.to_s(16).rjust(64, "0")].pack("H*") + s + v.chr },
      "64 bytes" => ->(r, s, _v, _n) { r + s }
    }.each do |shape, build|
      context "with #{shape}" do
        let(:signature) { build.call(r, s, v, order.to_i) }

        it { is_expected.to be_nil }
      end
    end
  end
end
