# frozen_string_literal: true

require "rails_helper"

RSpec.describe CacheService do
  let(:test_cache_service_class) do
    Class.new(described_class) do
      def initialize(key_suffix = nil, expires_in: nil)
        @key_suffix = key_suffix
        super(nil, expires_in: expires_in)
      end

      def cache_key
        "test_cache_service:#{@key_suffix}"
      end
    end
  end

  describe "#call" do
    let(:cache_service) { test_cache_service_class.new("test", expires_in: nil) }
    let(:cache_key) { cache_service.cache_key }
    let(:cached_value) { "cached_value" }
    let(:new_value) { "new_value" }

    context "when cache exists" do
      before do
        allow(Rails.cache).to receive(:read).with(cache_key).and_return(cached_value)
      end

      it "returns cached value without calling the block" do
        block_called = false
        result = cache_service.call {
          block_called = true
          new_value
        }

        expect(result).to eq(cached_value)
        expect(block_called).to be false
      end
    end

    context "when cache does not exist" do
      before do
        allow(Rails.cache).to receive(:read).with(cache_key).and_return(nil)
        allow(Rails.cache).to receive(:write)
      end

      it "calls the block and caches the result" do
        result = cache_service.call { new_value }

        expect(result).to eq(new_value)
        expect(Rails.cache).to have_received(:write).with(cache_key, new_value, expires_in: nil)
      end
    end

    context "when expires_in is zero" do
      let(:cache_service) { test_cache_service_class.new("test", expires_in: 0) }

      before do
        allow(Rails.cache).to receive(:read).with(cache_key).and_return(nil)
        allow(Rails.cache).to receive(:write)
      end

      it "calls the block but does not cache the result" do
        result = cache_service.call { new_value }

        expect(result).to eq(new_value)
        expect(Rails.cache).not_to have_received(:write)
      end
    end
  end

  describe "#call with lazy validation" do
    let(:tracking_cache_service_class) do
      Class.new(described_class) do
        def initialize(key_suffix = nil, expires_in: nil, invalidate_if_older_than: nil)
          @key_suffix = key_suffix
          super(nil, expires_in:, invalidate_if_older_than:)
        end

        def cache_key
          "tracking_cache_service:#{@key_suffix}"
        end

        private

        def track_created_at?
          true
        end
      end
    end

    let(:cache_key) { "tracking_cache_service:test" }
    let(:new_value) { "new_value" }

    before { allow(Rails.cache).to receive(:write) }

    it "wraps the stored value, falling back to the write time when no event was seen" do
      allow(Rails.cache).to receive(:read).with(cache_key).and_return(nil)

      freeze_time do
        result = tracking_cache_service_class.new("test").call { new_value }

        expect(result).to eq(new_value)
        expect(Rails.cache).to have_received(:write).with(
          cache_key,
          {"cached_at" => Time.current.iso8601(6), "value" => new_value},
          expires_in: nil
        )
      end
    end

    it "stamps cached_at with the last seen event timestamp, not the write time" do
      allow(Rails.cache).to receive(:read).with(cache_key).and_return(nil)
      last_seen_at = 3.hours.ago

      tracking_cache_service_class.new("test", invalidate_if_older_than: last_seen_at).call { new_value }

      expect(Rails.cache).to have_received(:write).with(
        cache_key,
        {"cached_at" => last_seen_at.iso8601(6), "value" => new_value},
        expires_in: nil
      )
    end

    it "keeps the sub-second precision so a re-read for the same event stays valid" do
      last_seen_at = Time.current.change(usec: 750_000)

      allow(Rails.cache).to receive(:read).with(cache_key).and_return(nil)
      tracking_cache_service_class.new("test", invalidate_if_older_than: last_seen_at).call { new_value }

      wrapped = nil
      expect(Rails.cache).to have_received(:write) { |_key, value, **| wrapped = value }

      allow(Rails.cache).to receive(:read).with(cache_key).and_return(wrapped)
      service = tracking_cache_service_class.new("test", invalidate_if_older_than: last_seen_at)

      block_called = false
      result = service.call { block_called = true }

      expect(result).to eq(new_value)
      expect(block_called).to be false
    end

    context "when a wrapped value exists" do
      let(:cached_at) { 1.hour.ago }
      let(:cached) { {"cached_at" => cached_at.iso8601, "value" => "cached_value"} }

      before { allow(Rails.cache).to receive(:read).with(cache_key).and_return(cached) }

      it "returns the unwrapped value when no newer event was ingested" do
        service = tracking_cache_service_class.new("test", invalidate_if_older_than: 2.hours.ago)

        block_called = false
        result = service.call { block_called = true }

        expect(result).to eq("cached_value")
        expect(block_called).to be false
      end

      it "recomputes when a more recent event was ingested" do
        service = tracking_cache_service_class.new("test", invalidate_if_older_than: Time.current)

        result = service.call { new_value }

        expect(result).to eq(new_value)
      end

      it "returns the unwrapped value when no last event timestamp is given" do
        result = tracking_cache_service_class.new("test").call { new_value }

        expect(result).to eq("cached_value")
      end
    end

    context "when a legacy unwrapped value exists" do
      before { allow(Rails.cache).to receive(:read).with(cache_key).and_return("legacy_value") }

      it "recomputes so the entry is rewritten in the new shape" do
        service = tracking_cache_service_class.new("test", invalidate_if_older_than: 1.hour.ago)

        result = service.call { new_value }

        expect(result).to eq(new_value)
      end
    end
  end

  describe "#expire_cache" do
    let(:cache_service) { test_cache_service_class.new("test") }
    let(:cache_key) { cache_service.cache_key }

    before do
      allow(Rails.cache).to receive(:delete)
    end

    it "deletes the cache" do
      cache_service.expire_cache

      expect(Rails.cache).to have_received(:delete).with(cache_key)
    end
  end

  describe ".expire_cache" do
    it "creates an instance and calls expire_cache" do
      test_class = test_cache_service_class
      instance = instance_double(test_class)

      allow(test_class).to receive(:new).with("test").and_return(instance)
      allow(instance).to receive(:expire_cache)

      test_class.expire_cache("test")

      expect(instance).to have_received(:expire_cache)
    end
  end

  describe "#cache_key" do
    it "raises NotImplementedError when called on the base class" do
      expect { described_class.new.cache_key }.to raise_error(NotImplementedError)
    end
  end
end
