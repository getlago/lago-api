# frozen_string_literal: true

require "rails_helper"

RSpec.describe Webhook do
  subject(:webhook) { build(:webhook) }

  it { is_expected.to belong_to(:webhook_endpoint) }
  it { is_expected.to belong_to(:object).optional }
  it { is_expected.to belong_to(:organization) }

  describe "#payload" do
    subject { webhook.payload }

    let(:webhook) { create(:webhook, payload:) }
    let(:original_payload) { Faker::Types.rb_hash(number: 3).stringify_keys }

    context "when payload stored as string" do
      let(:payload) { original_payload.to_json }

      it "returns payload as hash" do
        expect(subject).to eq(original_payload)
      end
    end

    context "when payload stored as hash" do
      let(:payload) { original_payload }

      it "returns payload as hash" do
        expect(subject).to eq(original_payload)
      end
    end
  end

  describe "#generate_headers" do
    subject { webhook.generate_headers }

    let(:webhook) { create(:webhook, webhook_endpoint:) }
    let(:webhook_endpoint) { create(:webhook_endpoint, signature_algo:) }

    context "when signature algorithm is JWT" do
      let(:signature_algo) { :jwt }

      it "returns headers" do
        expect(subject).to eq(
          "X-Lago-Signature" => webhook.jwt_signature,
          "X-Lago-Signature-Algorithm" => "jwt",
          "X-Lago-Unique-Key" => webhook.id
        )
      end
    end

    context "when signature algorithm is HMAC" do
      let(:signature_algo) { :hmac }

      it "returns headers" do
        expect(subject).to eq(
          "X-Lago-Signature" => webhook.hmac_signature,
          "X-Lago-Signature-Algorithm" => "hmac",
          "X-Lago-Unique-Key" => webhook.id
        )
      end
    end
  end

  describe "#jwt_signature" do
    let(:decoded_signature) do
      JWT.decode(
        webhook.jwt_signature,
        RsaPublicKey,
        true,
        {
          algorithm: "RS256",
          iss: ENV["LAGO_API_URL"],
          verify_iss: true
        }
      )
    end

    let(:expected_signature) do
      [
        {"data" => webhook.payload.to_json, "iss" => "https://api.lago.dev"},
        {"alg" => "RS256"}
      ]
    end

    it "generates a correct jwt signature" do
      expect(decoded_signature).to eq expected_signature
    end
  end

  describe "#hmac_signature" do
    subject { webhook.hmac_signature }

    let(:webhook) { create(:webhook) }

    let(:expected_signature) do
      hmac = OpenSSL::HMAC.digest(
        "sha-256",
        webhook.organization.hmac_key,
        webhook.payload.to_json
      )

      Base64.strict_encode64(hmac)
    end

    it "returns HMAC signature as base 64 encoded string" do
      expect(subject).to eq expected_signature
    end
  end
end
