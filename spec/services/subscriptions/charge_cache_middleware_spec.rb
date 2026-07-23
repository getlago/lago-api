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

      it "stores the value wrapped with its creation time" do
        freeze_time do
          middleware.call(charge_filter:) { [fee] }

          cached = Rails.cache.read(cache_key)
          expect(cached["cached_at"]).to eq(Time.current.iso8601(6))
          expect(JSON.parse(cached["value"]).first["amount_cents"]).to eq(999)
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
  end
end
