# frozen_string_literal: true

require "rails_helper"

describe X402::SignInWithX::Message do
  subject(:message) { described_class.build(payload) }

  let(:vectors) { JSON.parse(File.read(Rails.root.join("spec/fixtures/x402/sign_in_with_x/vectors.json"))) }

  let(:evm_payload) do
    {
      "domain" => "api.example.com",
      "address" => "0x0000000000000000000000000000000000000001",
      "statement" => "Sign in to access your purchased content",
      "uri" => "https://api.example.com/data",
      "version" => "1",
      "chainId" => "eip155:8453",
      "type" => "eip191",
      "nonce" => "abc123xyz",
      "issuedAt" => "2026-05-27T00:00:00Z",
      "expirationTime" => "2026-05-27T00:05:00Z",
      "requestId" => "request-1",
      "resources" => ["https://api.example.com/data"],
      "signature" => "0xdeadbeef"
    }
  end

  let(:solana_payload) do
    evm_payload.merge(
      "address" => "6nYoFimREYaxQZZqBv7vbSd6ozGS1J8uhAAgUXPtaYy6",
      "chainId" => "solana:5eykt4UsFv8P8NJdTREpY1vzqKqZKvdp",
      "type" => "ed25519"
    )
  end

  describe ".build" do
    context "with an EVM payload" do
      let(:payload) { evm_payload }

      let(:expected) do
        "api.example.com wants you to sign in with your Ethereum account:\n" \
          "0x0000000000000000000000000000000000000001\n\n" \
          "Sign in to access your purchased content\n\n" \
          "URI: https://api.example.com/data\n" \
          "Version: 1\n" \
          "Chain ID: 8453\n" \
          "Nonce: abc123xyz\n" \
          "Issued At: 2026-05-27T00:00:00Z\n" \
          "Expiration Time: 2026-05-27T00:05:00Z\n" \
          "Request ID: request-1\n" \
          "Resources:\n" \
          "- https://api.example.com/data"
      end

      it { is_expected.to eq(expected) }
    end

    context "with a Solana payload" do
      let(:payload) { solana_payload }

      let(:expected) do
        "api.example.com wants you to sign in with your Solana account:\n" \
          "6nYoFimREYaxQZZqBv7vbSd6ozGS1J8uhAAgUXPtaYy6\n\n" \
          "Sign in to access your purchased content\n\n" \
          "URI: https://api.example.com/data\n" \
          "Version: 1\n" \
          "Chain ID: 5eykt4UsFv8P8NJdTREpY1vzqKqZKvdp\n" \
          "Nonce: abc123xyz\n" \
          "Issued At: 2026-05-27T00:00:00Z\n" \
          "Expiration Time: 2026-05-27T00:05:00Z\n" \
          "Request ID: request-1\n" \
          "Resources:\n" \
          "- https://api.example.com/data"
      end

      it { is_expected.to eq(expected) }
    end

    context "without optional fields" do
      let(:payload) { evm_payload.except("expirationTime", "requestId", "resources") }

      let(:expected) do
        "api.example.com wants you to sign in with your Ethereum account:\n" \
          "0x0000000000000000000000000000000000000001\n\n" \
          "Sign in to access your purchased content\n\n" \
          "URI: https://api.example.com/data\n" \
          "Version: 1\n" \
          "Chain ID: 8453\n" \
          "Nonce: abc123xyz\n" \
          "Issued At: 2026-05-27T00:00:00Z"
      end

      it { is_expected.to eq(expected) }
    end

    context "with an empty resources array" do
      let(:payload) { evm_payload.except("expirationTime", "requestId").merge("resources" => []) }

      it { is_expected.to end_with("Issued At: 2026-05-27T00:00:00Z") }
    end

    context "with not before and request id but no expiration time" do
      let(:payload) { evm_payload.except("expirationTime", "resources").merge("notBefore" => "2026-05-26T23:59:00Z") }

      let(:expected) do
        "api.example.com wants you to sign in with your Ethereum account:\n" \
          "0x0000000000000000000000000000000000000001\n\n" \
          "Sign in to access your purchased content\n\n" \
          "URI: https://api.example.com/data\n" \
          "Version: 1\n" \
          "Chain ID: 8453\n" \
          "Nonce: abc123xyz\n" \
          "Issued At: 2026-05-27T00:00:00Z\n" \
          "Not Before: 2026-05-26T23:59:00Z\n" \
          "Request ID: request-1"
      end

      it { is_expected.to eq(expected) }
    end

    context "with an unsupported chain" do
      let(:payload) { evm_payload.merge("chainId" => "cosmos:cosmoshub-4") }

      it "raises an ArgumentError" do
        expect { message }.to raise_error(ArgumentError)
      end
    end

    describe "vectors" do
      let(:payload) { evm_payload }

      it "rebuilds every EVM and Solana vector message" do
        entries = vectors["evm"] + vectors["svm"]

        expect(entries.map { |entry| described_class.build(entry["payload"]) }).to eq(entries.map { |entry| entry["message"] })
      end
    end
  end
end
