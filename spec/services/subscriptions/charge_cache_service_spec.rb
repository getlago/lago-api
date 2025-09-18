# frozen_string_literal: true

require "rails_helper"

RSpec.describe Subscriptions::ChargeCacheService do
  subject(:cache_service) { described_class.new(subscription:, charge:, charge_filter:) }

  let(:subscription) { create(:subscription) }
  let(:charge) { create(:standard_charge, plan: subscription.plan) }
  let(:charge_filter) { nil }

  describe "#cache_key" do
    it "returns the cache key" do
      expect(cache_service.cache_key)
        .to eq("charge-usage/#{described_class::CACHE_KEY_VERSION}/#{charge.id}/#{subscription.id}/#{charge.updated_at.iso8601}")
    end

    context "with a charge filter" do
      let(:charge_filter) { create(:charge_filter) }

      it "returns the cache key with the charge filter" do
        expect(cache_service.cache_key)
          .to eq("charge-usage/#{described_class::CACHE_KEY_VERSION}/#{charge.id}/#{subscription.id}/#{charge.updated_at.iso8601}/#{charge_filter.id}/#{charge_filter.updated_at.iso8601}")
      end
    end
  end

  describe "#expire_cache" do
    it "deletes the cached value" do
      allow(Rails.cache).to receive(:delete).with(cache_service.cache_key)

      cache_service.expire_cache

      expect(Rails.cache).to have_received(:delete).with(cache_service.cache_key)
    end
  end
end
