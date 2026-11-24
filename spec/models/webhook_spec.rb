# frozen_string_literal: true

require "rails_helper"

RSpec.describe Webhook do
  subject(:webhook) { build(:webhook) }

  let_it_be(:organization) { create_default(:organization) }
  let_it_be(:customer) { create_default(:customer) }

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

    context "when payload stored on object storage" do
      let(:webhook) { create(:webhook, payload: nil) }

      before do
        webhook.store_payload(original_payload)
        webhook.save!
      end

      it "returns the payload read from object storage" do
        expect(described_class.find(webhook.id).payload).to eq(original_payload)
      end
    end
  end

  describe "#response" do
    subject { webhook.response }

    context "when response stored on object storage" do
      let(:webhook) { create(:webhook, response: nil) }
      let(:original_response) { {"status" => "ok"} }

      before do
        webhook.store_response(original_response)
        webhook.save!
      end

      it "returns the response read from object storage" do
        expect(described_class.find(webhook.id).response).to eq(original_response)
      end
    end

    context "when response stored in the database" do
      let(:webhook) { create(:webhook, :failed) }

      it "returns the response from the database" do
        expect(subject).to eq(webhook.read_attribute(:response))
      end
    end
  end

  describe "#store_payload" do
    subject(:webhook) { create(:webhook, payload: nil) }

    let(:content) { {"foo" => "bar"} }

    it "uploads the gzipped payload to object storage and stores the key" do
      key = webhook.store_payload(content)

      expect(key).to match(%r{\Awebhooks/\d{4}/\d{2}/\d{2}/[0-9a-f-]+/payload\.json\.gz\z})
      expect(webhook.payload_key).to eq(key)
      expect(ActiveSupport::Gzip.decompress(described_class.payload_storage.download(key))).to eq(content.to_json)
    end

    it "does not store the payload in the database" do
      webhook.store_payload(content)
      webhook.save!

      expect(webhook.reload.read_attribute(:payload)).to be_nil
      expect(webhook.payload).to eq(content)
    end
  end

  describe "#store_response" do
    subject(:webhook) { create(:webhook, payload: nil) }

    let(:content) { {"status" => "ok"} }

    it "uploads the gzipped response alongside the payload and stores the key" do
      webhook.store_payload({"foo" => "bar"})
      key = webhook.store_response(content)

      expect(key).to match(%r{\Awebhooks/\d{4}/\d{2}/\d{2}/[0-9a-f-]+/response\.json\.gz\z})
      expect(File.dirname(key)).to eq(File.dirname(webhook.payload_key))
      expect(ActiveSupport::Gzip.decompress(described_class.payload_storage.download(key))).to eq(content.to_json)
    end

    it "does not store the response in the database" do
      webhook.store_response(content)
      webhook.save!

      expect(webhook.reload.read_attribute(:response)).to be_nil
      expect(webhook.response).to eq(content)
    end

    context "when the upload fails" do
      before do
        allow(described_class.payload_storage).to receive(:upload).and_raise(StandardError.new("boom"))
      end

      it "falls back to storing the response in the database" do
        webhook.store_response(content)
        webhook.save!

        expect(webhook.response_key).to be_nil
        expect(webhook.reload.read_attribute(:response)).to eq(content)
        expect(webhook.response).to eq(content)
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

    context "when signature algorithm is Standard Webhooks" do
      let(:signature_algo) { :standard_webhooks }
      let(:webhook) do
        create(
          :webhook,
          webhook_endpoint:,
          id: "8b2f6a1e-3c4d-4e5f-9a6b-7c8d9e0f1a2b",
          payload: {"webhook_type" => "invoice.created", "amount_cents" => 100}
        )
      end

      before do
        # Secret: whsec_ + base64 of the 32 bytes 0x00..0x1f.
        create(:webhook_endpoint_signing_key, webhook_endpoint:, secret: "whsec_AAECAwQFBgcICQoLDA0ODxAREhMUFRYXGBkaGxwdHh8=")
      end

      around { |example| travel_to(Time.zone.at(1_762_300_800)) { example.run } }

      it "returns only the Standard Webhooks headers" do
        # printf '%s' '8b2f6a1e-3c4d-4e5f-9a6b-7c8d9e0f1a2b.1762300800.{"webhook_type":"invoice.created","amount_cents":100}' \
        #   | openssl dgst -sha256 -mac HMAC -macopt hexkey:000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f -binary | base64
        expect(subject).to eq(
          "webhook-id" => "8b2f6a1e-3c4d-4e5f-9a6b-7c8d9e0f1a2b",
          "webhook-timestamp" => "1762300800",
          "webhook-signature" => "v1,Kb+qawXvtjgaYfg4mZ5Nwx56fhXVFDUa+V+BmUirSEY="
        )
      end

      it "uses the time of each call as timestamp" do
        first_headers = webhook.generate_headers
        travel_to(Time.zone.at(1_762_304_400))

        # Same derivation as above with the timestamp 1762304400.
        expect(webhook.generate_headers).to eq(
          "webhook-id" => first_headers["webhook-id"],
          "webhook-timestamp" => "1762304400",
          "webhook-signature" => "v1,mUzwJIALxpDnPZ/2ZjpQp3aqBCSK3/sKsse6S6wfoEM="
        )
      end
    end
  end

  describe "#signing_key" do
    subject { webhook.signing_key }

    let(:webhook_endpoint) { create(:webhook_endpoint, signature_algo: :standard_webhooks) }
    let(:webhook) { create(:webhook, webhook_endpoint:) }

    context "when the endpoint has no signing key" do
      it { is_expected.to be_nil }
    end

    context "when the endpoint has a signing key" do
      let(:signing_key) { create(:webhook_endpoint_signing_key, webhook_endpoint:) }

      before { signing_key }

      it "returns the current key of the endpoint" do
        expect(subject).to eq(signing_key)
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
