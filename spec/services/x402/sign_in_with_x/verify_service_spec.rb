# frozen_string_literal: true

require "rails_helper"

describe X402::SignInWithX::VerifyService do
  include SignInWithXSigner

  subject(:result) { described_class.call(payload:, allowed_origins:, networks:) }

  let(:key) { siwx_evm_key }
  let(:payload) { signed_siwx(key) }
  let(:allowed_origins) { ["https://api.example.com"] }
  let(:networks) { ["eip155:84532"] }

  before { freeze_time }

  context "with a signed EVM proof" do
    it "returns the proven signer" do
      expect(result).to be_success
      expect(result).to have_attributes(address: siwx_address(key), family: :evm, nonce: payload["nonce"])
    end
  end

  JSON.parse(Rails.root.join("spec/fixtures/x402/sign_in_with_x/vectors.json").read)
    .slice("evm", "svm", "x402_client").each do |group, entries|
    entries.each do |entry|
      context "with the #{group} #{entry["name"]} vector" do
        let(:payload) { entry["payload"] }
        let(:networks) { [payload["chainId"]] }

        before { travel_to(Time.zone.parse("2026-10-16T10:01:00Z")) }

        it "returns the vector's signer" do
          expect(result).to be_success
          expect(result.address).to eq(payload["address"])
        end
      end
    end
  end

  context "with a payload that is not a Hash" do
    let(:payload) { "token" }

    it { expect(result.error.messages).to eq(siwx: ["value_is_invalid"]) }
  end

  %w[domain address statement uri version chainId type nonce issuedAt signature].each do |field|
    context "without #{field}" do
      let(:payload) { signed_siwx(key).except(field) }

      it { expect(result.error.messages).to eq(siwx: ["value_is_invalid"]) }
    end
  end

  context "with a numeric nonce" do
    let(:payload) { signed_siwx(key, nonce: 12_345_678) }

    it { expect(result.error.messages).to eq(siwx: ["value_is_invalid"]) }
  end

  context "with a null domain" do
    let(:payload) { signed_siwx(key).merge("domain" => nil) }

    it { expect(result.error.messages).to eq(siwx: ["value_is_invalid"]) }
  end

  context "with a numeric requestId" do
    let(:payload) { signed_siwx(key, requestId: 1) }

    it { expect(result.error.messages).to eq(siwx: ["value_is_invalid"]) }
  end

  context "with a nonce that is not valid UTF-8" do
    let(:payload) { signed_siwx(key).merge("nonce" => "abcd\xFFefgh".dup.force_encoding("UTF-8")) }

    it { expect(result.error.messages).to eq(siwx: ["value_is_invalid"]) }
  end

  context "with a line feed in the statement" do
    let(:payload) { signed_siwx(key, statement: "Sign in\nto use your credits") }

    it { expect(result.error.messages).to eq(siwx: ["value_is_invalid"]) }
  end

  context "with a carriage return in the uri" do
    let(:payload) { signed_siwx(key, uri: "https://api.example.com/v1/generate\r") }

    it { expect(result.error.messages).to eq(siwx: ["value_is_invalid"]) }
  end

  context "with an address of 513 characters" do
    let(:payload) { signed_siwx(key, address: "a" * 513) }

    it { expect(result.error.messages).to eq(siwx: ["value_is_invalid"]) }
  end

  context "with a signature of 16 385 characters" do
    let(:payload) { signed_siwx(key).merge("signature" => "0x#{"a" * 16_383}") }

    it { expect(result.error.messages).to eq(siwx: ["value_is_invalid"]) }
  end

  context "with resources given as a String" do
    let(:payload) { signed_siwx(key, resources: "https://api.example.com/v1/generate") }

    it { expect(result.error.messages).to eq(siwx: ["value_is_invalid"]) }
  end

  context "with 11 resources" do
    let(:payload) { signed_siwx(key, resources: Array.new(11) { |index| "https://api.example.com/v1/#{index}" }) }

    it { expect(result.error.messages).to eq(siwx: ["value_is_invalid"]) }
  end

  context "with a resource that is not a String" do
    let(:payload) { signed_siwx(key, resources: [1]) }

    it { expect(result.error.messages).to eq(siwx: ["value_is_invalid"]) }
  end

  context "with a line feed in a resource" do
    let(:payload) { signed_siwx(key, resources: ["https://api.example.com/v1\n- https://evil.example.com"]) }

    it { expect(result.error.messages).to eq(siwx: ["value_is_invalid"]) }
  end

  context "with an empty statement" do
    let(:payload) { signed_siwx(key, statement: "") }

    it { expect(result.error.messages).to eq(siwx: ["value_is_invalid"]) }
  end

  context "with an unparseable issuedAt" do
    let(:payload) { signed_siwx(key, issuedAt: "yesterday") }

    it { expect(result.error.messages).to eq(siwx: ["value_is_invalid"]) }
  end

  context "with an unparseable notBefore" do
    let(:payload) { signed_siwx(key, notBefore: "2026-13-45T10:00:00Z") }

    it { expect(result.error.messages).to eq(siwx: ["value_is_invalid"]) }
  end

  context "with version 2" do
    let(:payload) { signed_siwx(key, version: "2") }

    it { expect(result.error.messages).to eq(siwx: ["unsupported_version"]) }
  end

  context "with a mainnet chain on a testnet connection" do
    let(:payload) { signed_siwx(key, chainId: "eip155:8453") }

    it { expect(result.error.messages).to eq(siwx: ["unsupported_chain"]) }
  end

  context "with an unsupported chain" do
    let(:payload) { signed_siwx(key, chainId: "eip155:1") }

    it { expect(result.error.messages).to eq(siwx: ["unsupported_chain"]) }
  end

  context "with the ed25519 type on an EVM chain" do
    let(:payload) { signed_siwx(key, type: "ed25519") }

    it { expect(result.error.messages).to eq(siwx: ["unsupported_chain"]) }
  end

  context "with another domain" do
    let(:payload) { signed_siwx(key, domain: "evil.example.com") }

    it { expect(result.error.messages).to eq(siwx: ["domain_mismatch"]) }
  end

  context "with a uri on another host" do
    let(:payload) { signed_siwx(key, uri: "https://evil.example.com/v1") }

    it { expect(result.error.messages).to eq(siwx: ["uri_mismatch"]) }
  end

  context "with a uri over http" do
    let(:payload) { signed_siwx(key, uri: "http://api.example.com/v1") }

    it { expect(result.error.messages).to eq(siwx: ["uri_mismatch"]) }
  end

  context "with a localhost origin" do
    let(:allowed_origins) { ["http://localhost:3000"] }

    context "with the origin's host as domain" do
      let(:payload) { signed_siwx(key, domain: "localhost:3000", uri: "http://localhost:3000/v1") }

      it { expect(result).to be_success }
    end

    context "with a domain without the port" do
      let(:payload) { signed_siwx(key, domain: "localhost", uri: "http://localhost:3000/v1") }

      it { expect(result.error.messages).to eq(siwx: ["domain_mismatch"]) }
    end
  end

  context "with an issuedAt 6 minutes ago" do
    let(:payload) { signed_siwx(key, issuedAt: 6.minutes.ago.utc.iso8601(3)) }

    it { expect(result.error.messages).to eq(siwx: ["issued_at_too_old"]) }
  end

  context "with an issuedAt exactly 5 minutes ago" do
    let(:payload) { signed_siwx(key, issuedAt: 5.minutes.ago.utc.iso8601(3)) }

    it { expect(result).to be_success }
  end

  context "with an issuedAt 31 seconds ahead" do
    let(:payload) { signed_siwx(key, issuedAt: 31.seconds.from_now.utc.iso8601(3)) }

    it { expect(result.error.messages).to eq(siwx: ["issued_at_in_future"]) }
  end

  context "with an issuedAt 20 seconds ahead" do
    let(:payload) { signed_siwx(key, issuedAt: 20.seconds.from_now.utc.iso8601(3)) }

    it { expect(result).to be_success }
  end

  context "with an issuedAt exactly 30 seconds ahead" do
    let(:payload) { signed_siwx(key, issuedAt: 30.seconds.from_now.utc.iso8601(3)) }

    it { expect(result).to be_success }
  end

  context "with an issuedAt in another time zone" do
    let(:payload) { signed_siwx(key, issuedAt: (Time.current - 1.minute).in_time_zone("Paris").iso8601) }

    it { expect(result).to be_success }
  end

  context "with an expirationTime 1 second ago" do
    let(:payload) { signed_siwx(key, expirationTime: 1.second.ago.utc.iso8601(3)) }

    it { expect(result.error.messages).to eq(siwx: ["expired"]) }
  end

  context "with an expirationTime in 1 minute" do
    let(:payload) { signed_siwx(key, expirationTime: 1.minute.from_now.utc.iso8601(3)) }

    it { expect(result).to be_success }
  end

  context "with a notBefore in 1 minute" do
    let(:payload) { signed_siwx(key, notBefore: 1.minute.from_now.utc.iso8601(3)) }

    it { expect(result.error.messages).to eq(siwx: ["not_yet_valid"]) }
  end

  context "with a notBefore 1 minute ago" do
    let(:payload) { signed_siwx(key, notBefore: 1.minute.ago.utc.iso8601(3)) }

    it { expect(result).to be_success }
  end

  {"a 3-character nonce" => "abc", "a 65-character nonce" => "a" * 65, "a nonce with a dash" => "abc-1234"}.each do |shape, nonce|
    context "with #{shape}" do
      let(:payload) { signed_siwx(key, nonce:) }

      it { expect(result.error.messages).to eq(siwx: ["invalid_nonce"]) }
    end
  end

  context "with a lowercase address" do
    let(:payload) { signed_siwx(key, address: siwx_address(key).downcase) }

    it { expect(result.error.messages).to eq(siwx: ["invalid_address"]) }
  end

  context "with a statement changed after signing" do
    let(:payload) { signed_siwx(key).merge("statement" => "Sign in to use all your credits") }

    it { expect(result.error.messages).to eq(siwx: ["invalid_signature"]) }
  end

  context "with a proof signed by another key" do
    let(:payload) { signed_siwx(siwx_evm_key, address: siwx_address(key)) }

    it { expect(result.error.messages).to eq(siwx: ["invalid_signature"]) }
  end

  context "with a 64-byte signature" do
    let(:payload) { signed_siwx(key).then { |proof| proof.merge("signature" => proof["signature"].first(130)) } }

    it { expect(result.error.messages).to eq(siwx: ["invalid_signature"]) }
  end

  context "with a zeroed 65-byte signature" do
    let(:payload) { signed_siwx(key).merge("signature" => "0x#{"00" * 65}") }

    it { expect(result.error.messages).to eq(siwx: ["invalid_signature"]) }
  end

  context "with a non-hex signature" do
    let(:payload) { signed_siwx(key).merge("signature" => "0x#{"zz" * 65}") }

    it { expect(result.error.messages).to eq(siwx: ["invalid_signature"]) }
  end

  context "with an EIP-1271 signature" do
    let(:payload) { signed_siwx(key).merge("signature" => "0x#{"ab" * 600}") }

    it { expect(result.error.messages).to eq(siwx: ["invalid_signature"]) }
  end

  context "with a Solana proof on an EVM-only connection" do
    let(:key) { siwx_svm_key }

    it "returns the proven signer" do
      expect(result).to be_success
      expect(result).to have_attributes(address: siwx_address(key), family: :svm, nonce: payload["nonce"])
    end

    context "with the Solana mainnet chain" do
      let(:payload) { signed_siwx(key, chainId: "solana:5eykt4UsFv8P8NJdTREpY1vzqKqZKvdp") }

      it { expect(result.error.messages).to eq(siwx: ["unsupported_chain"]) }
    end

    context "with the statement changed after signing" do
      let(:payload) { signed_siwx(key).merge("statement" => "Sign in to use all your credits") }

      it { expect(result.error.messages).to eq(siwx: ["invalid_signature"]) }
    end

    context "with a small-order forgery" do
      let(:small_order_key) { "\x01".b + ("\x00" * 31).b }
      let(:payload) do
        signed_siwx(key).merge(
          "address" => X402::Base58.encode(small_order_key),
          "signature" => X402::Base58.encode(small_order_key + ("\x00" * 32).b)
        )
      end

      it { expect(result.error.messages).to eq(siwx: ["invalid_signature"]) }
    end

    context "with an address of 31 bytes" do
      let(:payload) { signed_siwx(key, address: X402::Base58.encode("\x02".b * 31)) }

      it { expect(result.error.messages).to eq(siwx: ["invalid_signature"]) }
    end

    context "with a signature that is not base58" do
      let(:payload) { signed_siwx(key).merge("signature" => "0x#{"ab" * 64}") }

      it { expect(result.error.messages).to eq(siwx: ["invalid_signature"]) }
    end
  end
end
