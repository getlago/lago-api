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

    context "when the lazy charge usage cache flag is enabled" do
      before { subscription.organization.enable_feature_flag!(:lazy_charge_usage_cache) }

      it "uses the lazy cache key version" do
        expect(cache_service.cache_key)
          .to eq("charge-usage/#{described_class::LAZY_CACHE_KEY_VERSION}/#{charge.id}/#{subscription.id}/#{charge.updated_at.iso8601}")
      end
    end

    context "with full usage" do
      subject(:cache_service) { described_class.new(subscription:, charge:, charge_filter:, full_usage: true) }

      it "returns a cache key distinct from the current usage one" do
        expect(cache_service.cache_key)
          .to eq("charge-usage/#{described_class::CACHE_KEY_VERSION}/#{charge.id}/#{subscription.id}/#{charge.updated_at.iso8601}/full-usage")
      end

      context "with a charge filter" do
        let(:charge_filter) { create(:charge_filter) }

        it "returns the cache key with the charge filter" do
          expect(cache_service.cache_key)
            .to eq("charge-usage/#{described_class::CACHE_KEY_VERSION}/#{charge.id}/#{subscription.id}/#{charge.updated_at.iso8601}/#{charge_filter.id}/#{charge_filter.updated_at.iso8601}/full-usage")
        end
      end
    end

    context "with prior periods" do
      subject(:cache_service) { described_class.new(subscription:, charge:, charge_filter:, prior_periods: true) }

      it "returns a cache key distinct from the current and full usage ones" do
        expect(cache_service.cache_key)
          .to eq("charge-usage/#{described_class::CACHE_KEY_VERSION}/#{charge.id}/#{subscription.id}/#{charge.updated_at.iso8601}/prior-periods")
      end

      context "with a charge filter" do
        let(:charge_filter) { create(:charge_filter) }

        it "returns the cache key with the charge filter" do
          expect(cache_service.cache_key)
            .to eq("charge-usage/#{described_class::CACHE_KEY_VERSION}/#{charge.id}/#{subscription.id}/#{charge.updated_at.iso8601}/#{charge_filter.id}/#{charge_filter.updated_at.iso8601}/prior-periods")
        end
      end

      context "when the lazy charge usage cache flag is enabled" do
        before { subscription.organization.enable_feature_flag!(:lazy_charge_usage_cache) }

        it "uses the lazy cache key version" do
          expect(cache_service.cache_key)
            .to eq("charge-usage/#{described_class::LAZY_CACHE_KEY_VERSION}/#{charge.id}/#{subscription.id}/#{charge.updated_at.iso8601}/prior-periods")
        end
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

  describe ".expire_cache" do
    let(:current_usage_key) { described_class.new(subscription:, charge:, charge_filter:).cache_key }
    let(:full_usage_key) { described_class.new(subscription:, charge:, charge_filter:, full_usage: true).cache_key }
    let(:prior_periods_key) { described_class.new(subscription:, charge:, charge_filter:, prior_periods: true).cache_key }

    # Both go unconditionally: removing usage (a deleted metric, de-duplicated events) does not
    # advance the ingestion watermark, so lazy validation would not clear what was left behind.
    it "deletes the current usage and full usage entries" do
      allow(Rails.cache).to receive(:delete)

      described_class.expire_cache(subscription:, charge:, charge_filter:)

      expect(Rails.cache).to have_received(:delete).with(current_usage_key)
      expect(Rails.cache).to have_received(:delete).with(full_usage_key)
    end

    it "does not delete the prior periods entry, which cannot exist without lazy validation" do
      allow(Rails.cache).to receive(:delete)

      described_class.expire_cache(subscription:, charge:, charge_filter:)

      expect(Rails.cache).not_to have_received(:delete).with(prior_periods_key)
    end

    context "when the lazy charge usage cache flag is enabled" do
      before { subscription.organization.enable_feature_flag!(:lazy_charge_usage_cache) }

      it "also deletes the prior periods entry" do
        allow(Rails.cache).to receive(:delete)

        described_class.expire_cache(subscription:, charge:, charge_filter:)

        expect(Rails.cache).to have_received(:delete).with(prior_periods_key)
      end
    end
  end

  describe ".expire_for_subscriptions" do
    let(:other_subscription) { create(:subscription, plan: subscription.plan) }
    let(:other_charge) { create(:standard_charge, plan: subscription.plan) }

    before do
      charge
      other_charge
      other_subscription
    end

    it "expires cache for each (subscription, charge) pair across the supplied ids" do
      allow(described_class).to receive(:expire_for_subscription_charge).and_call_original

      described_class.expire_for_subscriptions([subscription.id, other_subscription.id])

      [subscription, other_subscription].each do |sub|
        [charge, other_charge].each do |ch|
          expect(described_class).to have_received(:expire_for_subscription_charge)
            .with(subscription: having_attributes(id: sub.id), charge: having_attributes(id: ch.id))
        end
      end
    end

    it "loads plan, charges and filters in a constant number of queries" do
      ids = [subscription.id, other_subscription.id]

      query_count = 0
      counter = ->(*, payload) { query_count += 1 unless payload[:name]&.include?("SCHEMA") }

      ActiveSupport::Notifications.subscribed(counter, "sql.active_record") do
        described_class.expire_for_subscriptions(ids)
      end

      # 5 expected SELECTs: subscriptions, organizations, plans, charges, filters. Add a small
      # safety margin for incidental loads (e.g. activity log context).
      expect(query_count).to be <= 6
    end
  end

  describe ".expire_for_subscription" do
    it "delegates to .expire_for_subscriptions with the subscription's id" do
      allow(described_class).to receive(:expire_for_subscriptions).and_call_original

      described_class.expire_for_subscription(subscription)

      expect(described_class).to have_received(:expire_for_subscriptions).with([subscription.id])
    end
  end
end
