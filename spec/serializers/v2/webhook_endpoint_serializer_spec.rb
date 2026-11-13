# frozen_string_literal: true

require "rails_helper"

RSpec.describe V2::WebhookEndpointSerializer do
  subject(:payload) { described_class.new(webhook_endpoint, includes:).serialize }

  let(:webhook_endpoint) do
    create(:webhook_endpoint, name: "Billing events", signature_algo: :hmac, event_types: ["customer.created", "invoice.created"])
  end
  let(:includes) { [] }

  it "serializes the webhook endpoint without its organization" do
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

  context "with a standard_webhooks endpoint" do
    let(:webhook_endpoint) do
      create(
        :webhook_endpoint,
        name: "Billing events",
        signature_algo: :standard_webhooks,
        event_types: ["customer.created"],
        created_at: Time.zone.parse("2026-03-01T10:00:00.111111Z"),
        updated_at: Time.zone.parse("2026-03-02T10:00:00.222222Z")
      )
    end
    let(:newer_key) do
      create(:webhook_endpoint_signing_key, webhook_endpoint:, secret: "whsec_bmV3ZXI=", created_at: Time.zone.parse("2026-03-05T08:00:00.654321Z"))
    end
    let(:older_key) do
      create(:webhook_endpoint_signing_key, webhook_endpoint:, secret: "whsec_b2xkZXI=", created_at: Time.zone.parse("2026-03-03T08:00:00.123456Z"))
    end
    let(:flat_payload) do
      {
        lago_id: webhook_endpoint.id,
        name: "Billing events",
        webhook_url: webhook_endpoint.webhook_url,
        signature_algo: "standard_webhooks",
        event_types: ["customer.created"],
        created_at: "2026-03-01T10:00:00Z",
        updated_at: "2026-03-02T10:00:00Z"
      }
    end

    # Created newest first, so that the order of the list does not follow insertion.
    before do
      newer_key
      older_key
    end

    it "renders no signing keys without the expansion" do
      expect(payload).to eq(flat_payload)
    end

    context "with the signing_keys expansion of a v2 response" do
      let(:includes) { %i[signing_keys usec_timestamps] }

      it "renders the keys oldest first, with their creation time to the microsecond" do
        expect(payload).to eq(
          lago_id: webhook_endpoint.id,
          name: "Billing events",
          webhook_url: webhook_endpoint.webhook_url,
          signature_algo: "standard_webhooks",
          event_types: ["customer.created"],
          created_at: "2026-03-01T10:00:00.111111Z",
          updated_at: "2026-03-02T10:00:00.222222Z",
          signing_keys: [
            {lago_id: older_key.id, secret_key: "whsec_b2xkZXI=", created_at: "2026-03-03T08:00:00.123456Z"},
            {lago_id: newer_key.id, secret_key: "whsec_bmV3ZXI=", created_at: "2026-03-05T08:00:00.654321Z"}
          ]
        )
      end
    end

    context "when rendered as a webhook body" do
      subject(:payload) { described_class.new(webhook_endpoint).for_webhook!.serialize }

      it "never embeds the signing keys" do
        expect(payload).to eq(flat_payload)
      end
    end
  end

  context "with the signing_keys expansion on a jwt endpoint" do
    let(:webhook_endpoint) { create(:webhook_endpoint, signature_algo: :jwt) }
    let(:includes) { %i[signing_keys] }

    it "renders an empty list" do
      expect(payload[:signing_keys]).to eq([])
    end
  end

  context "with the signing_keys expansion on an hmac endpoint that kept a key" do
    let(:webhook_endpoint) { create(:webhook_endpoint, signature_algo: :hmac) }
    let(:includes) { %i[signing_keys] }

    before { create(:webhook_endpoint_signing_key, webhook_endpoint:) }

    it "renders an empty list" do
      expect(webhook_endpoint.signing_keys.count).to eq(1)
      expect(payload[:signing_keys]).to eq([])
    end
  end
end
