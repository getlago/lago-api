# frozen_string_literal: true

require "rails_helper"

RSpec.describe V2::WebhookEndpointSerializer do
  subject(:payload) { described_class.new(webhook_endpoint, includes:).serialize }

  let(:includes) { [] }
  let(:webhook_endpoint) do
    create(:webhook_endpoint, name: "Billing events", signature_algo: :hmac, event_types: ["customer.created", "invoice.created"])
  end

  it "serializes the webhook endpoint without its organization or signing keys" do
    expect(payload).to eq(
      lago_id: webhook_endpoint.id,
      name: "Billing events",
      webhook_url: webhook_endpoint.webhook_url,
      signature_algo: "hmac",
      event_types: ["customer.created", "invoice.created"],
      created_at: webhook_endpoint.created_at.iso8601,
      updated_at: webhook_endpoint.updated_at.iso8601
    )
  end

  context "when the endpoint receives every event type" do
    let(:webhook_endpoint) { create(:webhook_endpoint, event_types: nil) }

    it "renders null event types" do
      expect(payload[:event_types]).to be_nil
    end
  end

  context "with includes signing keys" do
    let(:includes) { [:signing_keys] }

    context "when the endpoint signs with standard webhooks" do
      let(:webhook_endpoint) { create(:webhook_endpoint, :standard_webhooks, name: "Billing events", event_types: nil) }
      let(:signing_key) { webhook_endpoint.signing_keys.usable.sole }

      before { create(:webhook_endpoint_signing_key, webhook_endpoint:, expires_at: 1.day.ago) }

      it "embeds its usable signing keys only" do
        expect(payload).to eq(
          lago_id: webhook_endpoint.id,
          name: "Billing events",
          webhook_url: webhook_endpoint.webhook_url,
          signature_algo: "standard_webhooks",
          event_types: nil,
          created_at: webhook_endpoint.created_at.iso8601,
          updated_at: webhook_endpoint.updated_at.iso8601,
          signing_keys: [{lago_id: signing_key.id, secret_key: signing_key.secret_key, created_at: signing_key.created_at.iso8601}]
        )
      end
    end

    context "when the endpoint signs with jwt and kept a secret from standard webhooks" do
      let(:webhook_endpoint) { create(:webhook_endpoint, signature_algo: :jwt) }

      before { create(:webhook_endpoint_signing_key, webhook_endpoint:) }

      it "renders no secret" do
        expect(payload[:signing_keys]).to eq([])
      end
    end
  end
end
