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
      let(:webhook_endpoint) do
        create(:webhook_endpoint, organization: create(:organization, feature_flags: ["standard_webhooks_signature"]), signature_algo:)
      end
      let(:secret) { "whsec_MfKQ9r8GKYqrTwjUPD8ILPZIo2LaLaSw" }
      let(:other_secret) { "whsec_#{Base64.strict_encode64("b" * 24)}" }
      let(:keys) { [{secret_key: secret, created_at: 2.days.ago}] }

      # Standard Webhooks: base64(HMAC-SHA256(base64-decoded secret without "whsec_", "{id}.{timestamp}.{body}"))
      def expected_signature(raw_secret)
        content = "#{webhook.id}.#{Time.current.to_i}.#{webhook.payload.to_json}"
        key = Base64.strict_decode64(raw_secret.delete_prefix("whsec_"))
        "v1," + Base64.strict_encode64(OpenSSL::HMAC.digest("SHA256", key, content))
      end

      before do
        freeze_time
        keys.each { |attrs| create(:webhook_endpoint_signing_key, webhook_endpoint:, **attrs) }
      end

      it "returns the Standard Webhooks headers only" do
        expect(subject).to eq(
          "webhook-id" => webhook.id,
          "webhook-timestamp" => Time.current.to_i.to_s,
          "webhook-signature" => expected_signature(secret)
        )
      end

      context "with two usable keys" do
        let(:keys) { [{secret_key: other_secret, created_at: 1.day.ago}, {secret_key: secret, created_at: 2.days.ago}] }

        it "sends one space-separated signature per key, oldest first" do
          expect(subject["webhook-signature"]).to eq("#{expected_signature(secret)} #{expected_signature(other_secret)}")
        end
      end

      context "with an expired key" do
        let(:keys) { [{secret_key: secret, created_at: 2.days.ago}, {secret_key: other_secret, created_at: 3.days.ago, expires_at: 1.second.ago}] }

        it "leaves the expired key out" do
          expect(subject["webhook-signature"]).to eq(expected_signature(secret))
        end
      end

      context "without any usable key" do
        let(:keys) { [{secret_key: secret, expires_at: 1.second.ago}] }

        it "raises without exposing the secret" do
          expect { subject }.to raise_error(described_class::MissingSigningKeyError) { |error|
            expect(error.message).to eq("No usable signing key for webhook endpoint #{webhook_endpoint.id}")
          }
        end
      end

      context "without any key" do
        let(:keys) { [] }

        it "raises" do
          expect { subject }.to raise_error(described_class::MissingSigningKeyError)
        end
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
