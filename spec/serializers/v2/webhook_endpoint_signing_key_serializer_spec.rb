# frozen_string_literal: true

require "rails_helper"

RSpec.describe V2::WebhookEndpointSigningKeySerializer do
  subject(:payload) { described_class.new(signing_key, includes:).serialize }

  let(:signing_key) do
    build_stubbed(:webhook_endpoint_signing_key, secret: "whsec_c2VjcmV0", created_at: Time.zone.parse("2026-03-04T05:06:07.123456Z"))
  end
  let(:includes) { [] }

  it "serializes the key with its creation time to the second" do
    expect(payload).to eq(
      lago_id: signing_key.id,
      secret_key: "whsec_c2VjcmV0",
      created_at: "2026-03-04T05:06:07Z"
    )
  end

  context "with the timestamp precision of a v2 response" do
    let(:includes) { %i[usec_timestamps] }

    it "renders the creation time to the microsecond" do
      expect(payload).to eq(
        lago_id: signing_key.id,
        secret_key: "whsec_c2VjcmV0",
        created_at: "2026-03-04T05:06:07.123456Z"
      )
    end
  end

  context "when embedded by the signing_keys expansion of a v2 webhook endpoint" do
    subject(:payload) do
      V2::WebhookEndpointSerializer.new(webhook_endpoint, includes: %i[signing_keys usec_timestamps]).serialize[:signing_keys]
    end

    let(:webhook_endpoint) { create(:webhook_endpoint, signature_algo: :standard_webhooks) }
    let(:signing_key) do
      create(:webhook_endpoint_signing_key, webhook_endpoint:, secret: "whsec_c2VjcmV0", created_at: Time.zone.parse("2026-03-04T05:06:07.123456Z"))
    end

    before { signing_key }

    it "renders each key with this serializer, to the microsecond" do
      expect(payload).to eq(
        [
          {lago_id: signing_key.id, secret_key: "whsec_c2VjcmV0", created_at: "2026-03-04T05:06:07.123456Z"}
        ]
      )
    end
  end
end
