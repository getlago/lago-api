# frozen_string_literal: true

require "rails_helper"

describe "Revoked API key Scenarios", cache: :redis do
  include_context "with mocked security logger"

  let(:organization) { create(:organization, webhook_url: nil) }
  let(:api_key) { organization.api_keys.first }
  let(:billable_metric) { create(:billable_metric, organization:) }

  before { create(:api_key, organization:) }

  def send_event(token)
    post(
      "/api/v1/events",
      params: {event: {code: billable_metric.code, transaction_id: SecureRandom.uuid}}.to_json,
      headers: {
        "Content-Type" => "application/json",
        "Accept" => "application/json",
        "Authorization" => "Bearer #{token}"
      }
    )
    response.status
  end

  # Runs `revoke` right after the next request reads the key from the database, before it writes the cache.
  def revoke_during_next_cache_miss
    revoked = false

    allow(ApiKeys::CacheService).to receive(:new).and_wrap_original do |new_service, *args, **kwargs|
      new_service.call(*args, **kwargs).tap do |service|
        allow(service).to receive(:fetch_from_database).and_wrap_original do |fetch_from_database|
          fetch_from_database.call.tap do
            next if revoked

            revoked = true
            revoke
          end
        end
      end
    end
  end

  shared_examples "a revoked api key" do
    it "rejects the key once it is revoked" do
      token = api_key.value
      expect(send_event(token)).to eq(200)

      revoke

      expect(send_event(token)).to eq(401)
    end

    it "rejects the key when a request reads it from the database while it is revoked" do
      token = api_key.value
      revoke_during_next_cache_miss

      expect(send_event(token)).to eq(200)
      expect(send_event(token)).to eq(401)
      expect(send_event(token)).to eq(401)
    end
  end

  context "when the api key is destroyed" do
    let(:revoke) { ApiKeys::DestroyService.call!(api_key) }

    it_behaves_like "a revoked api key"
  end

  context "when the api key is rotated" do
    let(:revoke) { ApiKeys::RotateService.call!(api_key:, params: {}) }

    it_behaves_like "a revoked api key"

    it "accepts the new key" do
      token = api_key.value
      expect(send_event(token)).to eq(200)

      new_api_key = revoke.api_key

      expect(send_event(token)).to eq(401)
      expect(send_event(new_api_key.value)).to eq(200)
    end
  end
end
