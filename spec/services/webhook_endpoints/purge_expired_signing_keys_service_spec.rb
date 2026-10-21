# frozen_string_literal: true

require "rails_helper"

RSpec.describe WebhookEndpoints::PurgeExpiredSigningKeysService do
  subject(:result) { described_class.call }

  let(:webhook_endpoint) { create(:webhook_endpoint) }
  let!(:active) { create(:webhook_endpoint_signing_key, webhook_endpoint:) }
  let!(:expiring) { create(:webhook_endpoint_signing_key, :expiring, webhook_endpoint:) }
  let!(:expired) { create(:webhook_endpoint_signing_key, :expired, webhook_endpoint:) }

  it "deletes only the keys past their expiry" do
    expect { result }.to change(WebhookEndpointSigningKey, :count).by(-1)
    expect(WebhookEndpointSigningKey.all).to match_array([active, expiring])
  end

  it "returns how many keys were purged" do
    expect(result.purged_count).to eq(1)
  end
end
