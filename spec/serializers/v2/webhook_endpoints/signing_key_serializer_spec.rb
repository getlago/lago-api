# frozen_string_literal: true

require "rails_helper"

RSpec.describe V2::WebhookEndpoints::SigningKeySerializer do
  subject(:payload) { described_class.new(signing_key).serialize }

  let(:signing_key) { create(:webhook_endpoint_signing_key) }

  it "serializes the signing key with its id and creation date" do
    expect(payload).to eq(
      lago_id: signing_key.id,
      secret_key: signing_key.secret_key,
      created_at: signing_key.created_at.iso8601
    )
  end
end
