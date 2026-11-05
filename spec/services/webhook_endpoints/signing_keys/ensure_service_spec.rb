# frozen_string_literal: true

require "rails_helper"

RSpec.describe WebhookEndpoints::SigningKeys::EnsureService do
  subject(:result) { described_class.call(webhook_endpoint:) }

  let_it_be(:organization) { create(:organization, feature_flags: ["standard_webhooks_signature"]) }
  let_it_be(:webhook_endpoint) { create(:webhook_endpoint, organization:, signature_algo: "standard_webhooks") }

  describe "#call" do
    context "when the endpoint has no key" do
      it "creates a key with a whsec_ secret" do
        expect { result }.to change(webhook_endpoint.signing_keys, :count).by(1)

        expect(result).to be_success
        expect(result.signing_key).to be_persisted
        expect(result.signing_key.organization).to eq(organization)
        expect(result.signing_key.webhook_endpoint).to eq(webhook_endpoint)
        expect(result.signing_key.secret_key).to start_with("whsec_")
      end
    end

    context "when the endpoint has a usable key" do
      let!(:signing_key) { create(:webhook_endpoint_signing_key, webhook_endpoint:) }

      it "returns it without creating a key" do
        expect { result }.not_to change(WebhookEndpointSigningKey, :count)

        expect(result).to be_success
        expect(result.signing_key).to eq(signing_key)
      end
    end

    context "when the endpoint has several usable keys" do
      let!(:oldest_key) { create(:webhook_endpoint_signing_key, webhook_endpoint:, created_at: 2.days.ago) }

      before { create(:webhook_endpoint_signing_key, webhook_endpoint:, created_at: 1.day.ago) }

      it "returns the oldest one" do
        expect(result.signing_key).to eq(oldest_key)
      end
    end

    context "when the only key of the endpoint is expired" do
      let!(:expired_key) { create(:webhook_endpoint_signing_key, webhook_endpoint:, expires_at: 1.minute.ago) }

      it "creates a new key" do
        expect { result }.to change(webhook_endpoint.signing_keys, :count).by(1)

        expect(result.signing_key).not_to eq(expired_key)
        expect(result.signing_key.expires_at).to be_nil
      end
    end

    context "when the key of another endpoint is usable" do
      before { create(:webhook_endpoint_signing_key, webhook_endpoint: create(:webhook_endpoint, organization:)) }

      it "creates a key for this endpoint" do
        expect { result }.to change(webhook_endpoint.signing_keys, :count).by(1)
      end
    end
  end
end
