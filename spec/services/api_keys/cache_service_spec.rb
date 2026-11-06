# frozen_string_literal: true

require "rails_helper"

RSpec.describe ApiKeys::CacheService, cache: :redis do
  subject(:cache_service) { described_class.new(auth_token, with_cache:) }

  let(:auth_token) { "token" }
  let(:with_cache) { false }

  describe "#cache_key" do
    it "returns the cache key" do
      expect(cache_service.cache_key).to eq("api_key/#{described_class::CACHE_KEY_VERSION}/token")
    end
  end

  describe "#expire_cache" do
    it "replaces the cached value with the invalidated marker" do
      Rails.cache.write(cache_service.cache_key, "cached")

      cache_service.expire_cache

      expect(Rails.cache.read(cache_service.cache_key)).to eq(described_class::INVALIDATED_MARKER)
    end
  end

  describe "INVALIDATED_MARKER" do
    it "reads as an expired cached key for the previous cache reader" do
      cache_json = JSON.parse(described_class::INVALIDATED_MARKER)
      api_key = ApiKey.instantiate(cache_json["api_key"].slice(*ApiKey.column_names))

      expect(api_key).to be_expired
    end
  end

  describe "#expire_all_cache" do
    let(:organization) { create(:organization, api_keys:) }
    let(:api_keys) { create_list(:api_key, 3) }

    it "invalidates all cached values" do
      allow(Rails.cache).to receive(:write)

      described_class.expire_all_cache(organization)

      expect(Rails.cache).to have_received(:write)
        .with(anything, described_class::INVALIDATED_MARKER, expires_in: described_class::INVALIDATED_MARKER_TTL)
        .exactly(3).times
    end
  end

  describe "#call" do
    let_it_be(:organization) { create_default(:organization) }
    let_it_be(:api_key) { create(:api_key) }
    let(:auth_token) { api_key.value }

    before { organization }

    it "returns the api_key and the organization" do
      expect(cache_service.call).to eq([api_key, organization])
    end

    context "when cache is enabled" do
      let(:with_cache) { true }

      before { Rails.cache.clear }

      it "returns the api_key and the organization and create the cache" do
        expect(cache_service.call).to eq([api_key, organization])

        expect(Rails.cache.read(cache_service.cache_key)).to be_present
      end

      context "when cache exists" do
        before { cache_service.call }

        it "returns the api_key and the organization" do
          expect(cache_service.call).to eq([api_key, organization])
        end
      end

      context "when the cache holds the invalidated marker" do
        before { cache_service.expire_cache }

        it "returns the api_key and the organization from the database without caching them" do
          expect(cache_service.call).to eq([api_key, organization])

          expect(Rails.cache.read(cache_service.cache_key)).to eq(described_class::INVALIDATED_MARKER)
        end
      end

      context "when the api key is revoked while a request is reading it" do
        include_context "with mocked security logger"

        let(:api_key) { create(:api_key) }
        let(:in_flight_request) { described_class.new(auth_token, with_cache: true) }

        before do
          create(:api_key)

          # Revoke the key after the in-flight request read it from the database, before it writes the cache.
          allow(in_flight_request).to receive(:fetch_from_database).and_wrap_original do |original|
            original.call.tap { revoke }
          end
        end

        context "with a destroyed api key" do
          let(:revoke) { ApiKeys::DestroyService.call(api_key) }

          it "does not cache the revoked api key" do
            expect(in_flight_request.call.first).to eq(api_key)

            expect(described_class.call(auth_token, with_cache: true)).to eq([nil, nil])
          end
        end

        context "with a rotated api key" do
          let(:revoke) { ApiKeys::RotateService.call(api_key:, params: {}) }

          it "does not cache the revoked api key" do
            expect(in_flight_request.call.first).to eq(api_key)

            expect(described_class.call(auth_token, with_cache: true)).to eq([nil, nil])
          end
        end
      end

      context "when cached value is expired" do
        let(:api_key) { create(:api_key, expires_at: Time.current - 10.minutes) }

        before do
          Rails.cache.write(cache_service.cache_key, {
            api_key: api_key.attributes,
            organization: organization.attributes
          }.to_json)
        end

        it "does not return the cache key and organization" do
          expect(cache_service.call).to eq([nil, nil])
        end
      end
    end
  end
end
