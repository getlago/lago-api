# frozen_string_literal: true

require "rails_helper"

describe X402::Payments::ComputeDigestService do
  subject(:result) { described_class.call(payment:, network:, asset:) }

  let(:network) { "eip155:84532" }
  let(:asset) { "0x036CbD53842c5426634e7929541eC2318f3dCF7e" }
  let(:authorization) do
    {
      "from" => "0xfB6916095ca1df60bB79Ce92cE3Ea74c37c5d359",
      "to" => "0x5aAeb6053F3E94C9b9A09f33669435E7Ef1BeAed",
      "value" => "1000000",
      "validAfter" => "0",
      "validBefore" => "1790300000",
      "nonce" => "0x#{"ab" * 32}"
    }
  end
  let(:payment) do
    {
      "x402Version" => 2,
      "resource" => {"url" => "https://api.example.com/report"},
      "accepted" => {"scheme" => "exact", "network" => network, "amount" => "1000000", "asset" => asset},
      "payload" => {"signature" => "0x#{"12" * 65}", "authorization" => authorization},
      "extensions" => {}
    }
  end

  def digest_of(other_payment, other_network: network, other_asset: asset)
    described_class.call(payment: other_payment, network: other_network, asset: other_asset).digest
  end

  it "returns a SHA-256 hex digest" do
    expect(result.digest).to match(/\A\h{64}\z/)
  end

  context "with the envelope respelled" do
    let(:respelled) do
      {
        payload: {
          authorization: {
            nonce: "0x#{"AB" * 32}",
            validBefore: 1_790_300_000,
            validAfter: 0,
            value: 1_000_000,
            to: authorization["to"].downcase,
            from: authorization["from"].downcase
          },
          signature: "0x#{"34" * 65}"
        },
        accepted: {"scheme" => "exact", "network" => network, "amount" => "1000000", "asset" => asset.downcase, "extra" => {}},
        x402Version: 2
      }
    end

    it "gives the same digest" do
      expect(digest_of(respelled)).to eq(result.digest)
    end
  end

  context "with a v1 wrapper around the same authorization" do
    let(:v1_payment) { {"x402Version" => 1, "scheme" => "exact", "network" => "base-sepolia", "payload" => payment["payload"]} }

    it "gives the same digest" do
      expect(digest_of(v1_payment)).to eq(result.digest)
    end
  end

  it "keys on the asset contract whatever its case" do
    expect(digest_of(payment, other_asset: asset.downcase)).to eq(result.digest)
  end

  context "with another nonce" do
    let(:other) { payment.deep_merge("payload" => {"authorization" => {"nonce" => "0x#{"cd" * 32}"}}) }

    it "gives another digest" do
      expect(digest_of(other)).not_to eq(result.digest)
    end
  end

  it "gives another digest for another token contract" do
    expect(digest_of(payment, other_asset: "0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913")).not_to eq(result.digest)
  end

  it "gives another digest on another network" do
    expect(digest_of(payment, other_network: "eip155:8453")).not_to eq(result.digest)
  end

  context "with a Solana payment" do
    let(:network) { "solana:EtWTRABZaYq6iMfeYKouRu166VU2xqa1" }
    let(:asset) { nil }
    let(:transaction) { Base64.strict_encode64("\x01".b + ("\x00".b * 64) + ("\x80".b * 40)) }
    let(:payment) { {"x402Version" => 2, "accepted" => {"network" => network}, "payload" => {"transaction" => transaction}} }

    it "returns a digest" do
      expect(result.digest).to match(/\A\h{64}\z/)
    end

    it "ignores the envelope" do
      expect(digest_of({"payload" => {"transaction" => transaction}})).to eq(result.digest)
    end

    it "gives another digest for other bytes" do
      expect(digest_of({"payload" => {"transaction" => Base64.strict_encode64("other".b)}})).not_to eq(result.digest)
    end

    context "when the transaction is not base64" do
      let(:transaction) { "not base64!" }

      it "fails on the transaction" do
        expect(result.error.messages).to eq(payment: ["invalid_transaction"])
      end
    end

    context "without a transaction" do
      let(:payment) { {"payload" => {}} }

      it "fails on the transaction" do
        expect(result.error.messages).to eq(payment: ["invalid_transaction"])
      end
    end
  end

  describe "malformed payments" do
    shared_examples "a malformed payment" do |code|
      it "fails with #{code}" do
        expect(result.error).to be_a(BaseService::ValidationFailure)
      end

      it "names the payment" do
        expect(result.error.messages).to eq(payment: [code])
      end
    end

    context "when the payment is not a hash" do
      let(:payment) { "PAYMENT-SIGNATURE" }

      it_behaves_like "a malformed payment", "invalid_payment"
    end

    context "when the network namespace is unknown" do
      let(:network) { "sui:mainnet" }

      it_behaves_like "a malformed payment", "unsupported_network"
    end

    context "when the asset is not an EVM address" do
      let(:asset) { "USDC" }

      it_behaves_like "a malformed payment", "invalid_asset"
    end

    context "when the payload is not an object" do
      let(:payment) { {"payload" => "0xdeadbeef"} }

      it_behaves_like "a malformed payment", "invalid_authorization"
    end

    context "without an authorization" do
      let(:payment) { {"payload" => {"signature" => "0x00"}} }

      it_behaves_like "a malformed payment", "invalid_authorization"
    end

    %w[from to value validAfter validBefore nonce].each do |field|
      context "without #{field}" do
        let(:payment) { {"payload" => {"authorization" => authorization.except(field)}} }

        it_behaves_like "a malformed payment", "invalid_authorization"
      end
    end

    context "when the nonce is not 32 bytes of hex" do
      let(:payment) { {"payload" => {"authorization" => authorization.merge("nonce" => "0xabcd")}} }

      it_behaves_like "a malformed payment", "invalid_authorization"
    end

    context "when from is not an EVM address" do
      let(:payment) { {"payload" => {"authorization" => authorization.merge("from" => "2wKupLR9q6wXYppw8Gr2NvWxKBUqm4PPJKkQfoxHDBg4")}} }

      it_behaves_like "a malformed payment", "invalid_authorization"
    end

    [1.5, "1.5", "010x", "0x10", "1_000", "-1", -1].each do |value|
      context "when the value is #{value.inspect}" do
        let(:payment) { {"payload" => {"authorization" => authorization.merge("value" => value)}} }

        it_behaves_like "a malformed payment", "invalid_authorization"
      end
    end

    context "when the value has a leading zero" do
      let(:payment) { {"payload" => {"authorization" => authorization.merge("value" => "01000000")}} }

      it "reads it as decimal" do
        expect(result.digest).to eq(digest_of({"payload" => {"authorization" => authorization}}))
      end
    end
  end
end
