# frozen_string_literal: true

require "rails_helper"

RSpec.describe ::V1::WebhookEndpointSerializer do
  subject(:payload) { JSON.parse(serializer.to_json)["webhook_endpoint"] }

  let(:serializer) { described_class.new(webhook_endpoint, root_name: "webhook_endpoint", includes:) }
  let(:includes) { [] }
  let(:organization) { create(:organization, feature_flags: ["standard_webhooks_signature"]) }
  let(:webhook_endpoint) do
    create(:webhook_endpoint, organization:, name: "Billing events", signature_algo: :jwt, event_types: ["customer.created", "invoice.created"])
  end

  it "serializes the webhook endpoint without its signing keys" do
    expect(payload).to eq(
      "lago_id" => webhook_endpoint.id,
      "lago_organization_id" => webhook_endpoint.organization_id,
      "webhook_url" => webhook_endpoint.webhook_url,
      "signature_algo" => "jwt",
      "name" => "Billing events",
      "event_types" => ["customer.created", "invoice.created"],
      "created_at" => webhook_endpoint.created_at.iso8601
    )
  end

  context "when the endpoint signs with standard webhooks" do
    let(:webhook_endpoint) do
      create(:webhook_endpoint, organization:, name: "Billing events", signature_algo: :standard_webhooks, event_types: nil)
    end
    # Ids sort against creation, so a query ordered by id alone would put the newer key first.
    let(:older_key) do
      create(:webhook_endpoint_signing_key, webhook_endpoint:, id: "ffffffff-ffff-4fff-bfff-ffffffffffff", created_at: 2.days.ago)
    end
    let(:newer_key) do
      create(:webhook_endpoint_signing_key, webhook_endpoint:, id: "00000000-0000-4000-8000-000000000000", created_at: 1.day.ago)
    end

    before do
      older_key
      newer_key
      create(:webhook_endpoint_signing_key, webhook_endpoint:, created_at: 1.hour.ago, expires_at: 1.minute.ago)
    end

    context "with includes signing keys" do
      let(:includes) { [:signing_keys] }

      it "renders the usable signing keys, oldest first" do
        expect(payload).to eq(
          "lago_id" => webhook_endpoint.id,
          "lago_organization_id" => webhook_endpoint.organization_id,
          "webhook_url" => webhook_endpoint.webhook_url,
          "signature_algo" => "standard_webhooks",
          "name" => "Billing events",
          "event_types" => nil,
          "created_at" => webhook_endpoint.created_at.iso8601,
          "signing_keys" => [
            {"lago_id" => older_key.id, "secret_key" => older_key.secret_key, "created_at" => older_key.created_at.iso8601},
            {"lago_id" => newer_key.id, "secret_key" => newer_key.secret_key, "created_at" => newer_key.created_at.iso8601}
          ]
        )
        expect(newer_key.secret_key).to start_with("whsec_")
      end

      context "when two usable keys were created at the same time" do
        let(:newer_key) do
          create(:webhook_endpoint_signing_key, webhook_endpoint:, id: "00000000-0000-4000-8000-000000000000", created_at: older_key.created_at)
        end

        it "orders them by id" do
          expect(payload["signing_keys"].pluck("lago_id")).to eq([newer_key.id, older_key.id])
        end
      end
    end

    context "without includes signing keys" do
      it "renders no signing keys" do
        expect(payload).not_to have_key("signing_keys")
        expect(payload["signature_algo"]).to eq("standard_webhooks")
      end
    end
  end

  context "when every signing key of the standard webhooks endpoint has expired" do
    let(:includes) { [:signing_keys] }
    let(:webhook_endpoint) do
      create(:webhook_endpoint, organization:, name: "Billing events", signature_algo: :standard_webhooks, event_types: nil)
    end

    before { create(:webhook_endpoint_signing_key, webhook_endpoint:, expires_at: 1.minute.ago) }

    it "renders an empty list" do
      expect(payload["signing_keys"]).to eq([])
      expect(payload["signature_algo"]).to eq("standard_webhooks")
    end
  end

  context "when the endpoint signs with jwt and kept a secret from standard webhooks" do
    let(:includes) { [:signing_keys] }

    before { create(:webhook_endpoint_signing_key, webhook_endpoint:) }

    it "renders an empty list" do
      expect(payload).to eq(
        "lago_id" => webhook_endpoint.id,
        "lago_organization_id" => webhook_endpoint.organization_id,
        "webhook_url" => webhook_endpoint.webhook_url,
        "signature_algo" => "jwt",
        "name" => "Billing events",
        "event_types" => ["customer.created", "invoice.created"],
        "created_at" => webhook_endpoint.created_at.iso8601,
        "signing_keys" => []
      )
    end
  end
end
