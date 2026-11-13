# frozen_string_literal: true

require "rails_helper"

RSpec.describe ::V1::WebhookEndpointSerializer do
  subject(:serializer) { described_class.new(webhook_endpoint, root_name: "webhook_endpoint", includes:) }

  let(:webhook_endpoint) { create(:webhook_endpoint, name: "Billing", event_types: ["customer.created"]) }
  let(:includes) { [] }

  let(:expected_fields) do
    {
      "lago_id" => webhook_endpoint.id,
      "lago_organization_id" => webhook_endpoint.organization_id,
      "webhook_url" => webhook_endpoint.webhook_url,
      "signature_algo" => "jwt",
      "name" => "Billing",
      "event_types" => ["customer.created"],
      "created_at" => webhook_endpoint.created_at.iso8601
    }
  end

  it "serializes the object without signing_keys" do
    result = JSON.parse(serializer.to_json)

    expect(result["webhook_endpoint"]).to eq(expected_fields)
  end

  context "with a standard_webhooks endpoint that has a signing key" do
    let(:webhook_endpoint) do
      create(:webhook_endpoint, name: "Billing", event_types: ["customer.created"], signature_algo: :standard_webhooks)
    end
    let(:signing_key) do
      travel_to(Time.zone.parse("2026-01-01 10:00:00")) { create(:webhook_endpoint_signing_key, webhook_endpoint:) }
    end

    before { signing_key }

    it "leaves signing_keys out without the include" do
      result = JSON.parse(serializer.to_json)

      expect(result["webhook_endpoint"]).to eq(expected_fields.merge("signature_algo" => "standard_webhooks"))
    end

    context "with the signing_keys include" do
      let(:includes) { [:signing_keys] }

      it "serializes the exposed signing keys" do
        result = JSON.parse(serializer.to_json)

        expect(result["webhook_endpoint"]).to eq(
          expected_fields.merge(
            "signature_algo" => "standard_webhooks",
            "signing_keys" => [
              {
                "lago_id" => signing_key.id,
                "secret_key" => signing_key.secret,
                "created_at" => "2026-01-01T10:00:00Z"
              }
            ]
          )
        )
        expect(signing_key.secret).to start_with("whsec_")
      end
    end
  end
end
