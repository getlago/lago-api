# frozen_string_literal: true

require "rails_helper"

RSpec.describe Subscriptions::ChargeCacheMiddleware do
  subject(:middleware) do
    described_class.new(subscription:, charge:, to_datetime:, cache: cache_enabled, last_seen_at:)
  end

  let(:subscription) { create(:subscription) }
  let(:charge) { create(:standard_charge, plan: subscription.plan) }
  let(:to_datetime) { Time.current + 1.day }
  let(:cache_enabled) { true }
  let(:last_seen_at) { {} }
  let(:charge_filter) { nil }

  let(:cache_key) do
    Subscriptions::ChargeCacheService.new(subscription:, charge:, charge_filter:).cache_key
  end

  before do
    subscription.organization.enable_feature_flag!(:lazy_charge_usage_cache)
    Rails.cache.clear
  end

  describe "#call", cache: :memory do
    context "when caching is disabled" do
      let(:cache_enabled) { false }

      it "yields and returns the block result without touching the cache" do
        fees = [build(:charge_fee, subscription:, charge:)]
        allow(Rails.cache).to receive(:read)

        result = middleware.call(charge_filter:) { fees }

        expect(result).to eq(fees)
        expect(Rails.cache).not_to have_received(:read)
      end
    end

    context "when the cache is empty" do
      let(:fee) { build(:charge_fee, subscription:, charge:, amount_cents: 999) }

      it "computes and returns the rebuilt fees" do
        result = middleware.call(charge_filter:) { [fee] }

        expect(result.map(&:amount_cents)).to eq([999])
      end

      # No event has been seen for this charge yet (last_seen_at is empty), so cached_at falls back to
      # the settle bound rather than Time.current. Stepping a full window back is what guarantees the
      # first event to arrive invalidates the entry: ClickHouse floors enriched_at to the second, so
      # an event inserted just after the write is recorded at floor(write_time), which is always
      # greater than write_time - SETTLE_WINDOW but not necessarily greater than write_time itself.
      it "stores the value wrapped with the settle bound when no event was seen" do
        freeze_time do
          middleware.call(charge_filter:) { [fee] }

          cached = Rails.cache.read(cache_key)
          expect(cached["cached_at"]).to eq((Time.current - CacheService::SETTLE_WINDOW).iso8601(6))
          expect(JSON.parse(cached["value"]).first["amount_cents"]).to eq(999)
        end
      end

      context "when an event was already seen for the charge" do
        let(:last_seen_at) { {nil => 2.hours.ago} }

        it "stamps cached_at with the last seen event timestamp" do
          middleware.call(charge_filter:) { [fee] }

          cached = Rails.cache.read(cache_key)
          expect(cached["cached_at"]).to eq(last_seen_at[nil].iso8601(6))
        end
      end
    end

    context "when a valid cache entry exists" do
      before do
        Rails.cache.write(
          cache_key,
          {"cached_at" => 1.hour.ago.iso8601, "value" => [{"amount_cents" => 500}].to_json}
        )
      end

      it "returns the cached fees without calling the block" do
        block_called = false
        result = middleware.call(charge_filter:) do
          block_called = true
          []
        end

        expect(block_called).to be false
        expect(result.map(&:amount_cents)).to eq([500])
      end

      context "when a more recent event was ingested for the charge" do
        let(:last_seen_at) { {nil => Time.current} }

        it "recomputes by calling the block" do
          fee = build(:charge_fee, subscription:, charge:, amount_cents: 777)

          result = middleware.call(charge_filter:) { [fee] }

          expect(result.map(&:amount_cents)).to eq([777])
        end
      end

      context "when an older event was ingested for the charge" do
        let(:last_seen_at) { {nil => 2.hours.ago} }

        it "returns the cached fees without calling the block" do
          block_called = false
          result = middleware.call(charge_filter:) do
            block_called = true
            []
          end

          expect(block_called).to be false
          expect(result.map(&:amount_cents)).to eq([500])
        end
      end
    end

    context "with a charge filter" do
      let(:charge_filter) { create(:charge_filter, charge:) }
      let(:last_seen_at) { {charge_filter.id => Time.current} }

      before do
        Rails.cache.write(
          cache_key,
          {"cached_at" => 1.hour.ago.iso8601, "value" => [{"amount_cents" => 500}].to_json}
        )
      end

      it "looks up the last seen timestamp by charge and filter" do
        fee = build(:charge_fee, subscription:, charge:, amount_cents: 321)

        result = middleware.call(charge_filter:) { [fee] }

        expect(result.map(&:amount_cents)).to eq([321])
      end
    end

    context "when the cached fee carries a pricing unit usage and presentation breakdowns" do
      let(:pricing_unit_usage) { build(:pricing_unit_usage) }
      let(:fee) do
        build(:charge_fee, subscription:, charge:, amount_cents: 42, pricing_unit_usage:)
      end

      it "reconstructs them from the cache" do
        result = middleware.call(charge_filter:) { [fee] }

        expect(result.first.amount_cents).to eq(42)
        expect(result.first.pricing_unit_usage).to be_present
      end
    end

    context "with prior periods" do
      subject(:middleware) do
        described_class.new(subscription:, charge:, to_datetime:, cache: cache_enabled, prior_periods: true, context: "some-context", last_seen_at:)
      end

      let(:prior_periods_cache_key) do
        Subscriptions::ChargeCacheService.new(subscription:, charge:, charge_filter:, prior_periods: true).cache_key
      end

      it "passes prior_periods and context through to the cache service" do
        allow(Subscriptions::ChargeCacheService).to receive(:new).and_call_original

        middleware.call(charge_filter:) { [] }

        expect(Subscriptions::ChargeCacheService).to have_received(:new)
          .with(hash_including(prior_periods: true, context: "some-context"))
      end

      context "when a more recent event was ingested for the charge" do
        let(:last_seen_at) { {nil => Time.current} }

        before do
          Rails.cache.write(
            prior_periods_cache_key,
            {"cached_at" => 1.hour.ago.iso8601, "context" => "some-context", "value" => [{"amount_cents" => 500}].to_json}
          )
        end

        it "still returns the cached fees without calling the block" do
          block_called = false
          result = middleware.call(charge_filter:) do
            block_called = true
            []
          end

          expect(block_called).to be false
          expect(result.map(&:amount_cents)).to eq([500])
        end
      end
    end
  end

  describe ".prior_periods_expiration" do
    it "defaults to one day" do
      expect(described_class.prior_periods_expiration).to eq(described_class::DEFAULT_PRIOR_PERIODS_EXPIRATION)
    end

    context "when LAGO_PRIOR_PERIODS_USAGE_CACHE_TTL_SECONDS is set" do
      before { stub_const("ENV", ENV.to_hash.merge("LAGO_PRIOR_PERIODS_USAGE_CACHE_TTL_SECONDS" => "3600")) }

      it "returns the overridden expiration" do
        expect(described_class.prior_periods_expiration).to eq(3_600.seconds)
      end
    end
  end
end
