# frozen_string_literal: true

require "rails_helper"

RSpec.describe V2::WebhookEndpointSerializer do
  subject(:payload) { described_class.new(webhook_endpoint).serialize }

  let(:webhook_endpoint) do
    create(:webhook_endpoint, name: "Billing events", signature_algo: :hmac, event_types: ["customer.created", "invoice.created"])
  end

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
end
