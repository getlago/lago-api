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

    # Writes an entry through the service and returns the wrapped hash handed to Rails.cache (nil
    # when the service refused to cache), so a second call can read it back the way a subsequent
    # usage query would. invalidate_if_older_than must be older than SETTLE_WINDOW for a write.
    def write_entry(computed_at:, invalidate_if_older_than: nil, value: "new_value")
      allow(Rails.cache).to receive(:read).with(cache_key).and_return(nil)

      wrapped = nil
      allow(Rails.cache).to receive(:write) { |_key, written, **| wrapped = written }

      travel_to(computed_at, with_usec: true) do
        tracking_cache_service_class.new("test", invalidate_if_older_than:).call { value }
      end

      wrapped
    end

    # Replays a usage query against an already stored entry, returning [result, block_called].
    def read_entry(wrapped, invalidate_if_older_than:)
      allow(Rails.cache).to receive(:read).with(cache_key).and_return(wrapped)

      block_called = false
      result = tracking_cache_service_class.new("test", invalidate_if_older_than:).call do
        block_called = true
        "recomputed"
      end

      [result, block_called]
    end

    describe "stamping" do
      it "stamps cached_at with the last seen event timestamp, not the computation time" do
        allow(Rails.cache).to receive(:read).with(cache_key).and_return(nil)
        last_seen_at = Time.zone.parse("2026-07-27T10:00:00.123Z")
        computed_at = Time.zone.parse("2026-07-27T10:05:00.000Z")

        travel_to(computed_at, with_usec: true) do
          tracking_cache_service_class.new("test", invalidate_if_older_than: last_seen_at).call { new_value }
        end

        expect(Rails.cache).to have_received(:write).with(
          cache_key,
          {"cached_at" => last_seen_at.iso8601(6), "value" => new_value},
          expires_in: nil
        )
      end

      it "keeps the sub-second precision of the last seen event timestamp" do
        allow(Rails.cache).to receive(:read).with(cache_key).and_return(nil)
        last_seen_at = Time.zone.parse("2026-07-27T10:00:00.750Z")

        travel_to(last_seen_at + 1.hour, with_usec: true) do
          tracking_cache_service_class.new("test", invalidate_if_older_than: last_seen_at).call { new_value }
        end

        expect(Rails.cache).to have_received(:write).with(
          cache_key,
          {"cached_at" => "2026-07-27T10:00:00.750000Z", "value" => new_value},
          expires_in: nil
        )
      end

      it "falls back to the settle bound, never Time.current, when no event was seen" do
        allow(Rails.cache).to receive(:read).with(cache_key).and_return(nil)
        computed_at = Time.zone.parse("2026-07-27T10:00:00.500Z")

        travel_to(computed_at, with_usec: true) do
          tracking_cache_service_class.new("test").call { new_value }
        end

        expect(Rails.cache).to have_received(:write).with(
          cache_key,
          {"cached_at" => (computed_at - described_class::SETTLE_WINDOW).iso8601(6), "value" => new_value},
          expires_in: nil
        )
      end

      it "takes the fallback bound before the block runs, not after it returns" do
        allow(Rails.cache).to receive(:read).with(cache_key).and_return(nil)
        started_at = Time.zone.parse("2026-07-27T10:00:00.500Z")

        travel_to(started_at, with_usec: true) do
          tracking_cache_service_class.new("test").call do
            # The aggregation is the slow part: simulate it taking 30 seconds.
            travel_to(started_at + 30.seconds, with_usec: true)
            new_value
          end
        end

        expect(Rails.cache).to have_received(:write).with(
          cache_key,
          {"cached_at" => (started_at - described_class::SETTLE_WINDOW).iso8601(6), "value" => new_value},
          expires_in: nil
        )
      end
    end

    describe "settle window" do
      let(:boundary) { Time.zone.parse("2026-07-27T10:00:00.000Z") }

      it "does not cache a value computed while the boundary is still unsettled" do
        allow(Rails.cache).to receive(:read).with(cache_key).and_return(nil)

        travel_to(boundary + 0.4.seconds, with_usec: true) do
          result = tracking_cache_service_class.new("test", invalidate_if_older_than: boundary).call { new_value }

          expect(result).to eq(new_value)
        end

        expect(Rails.cache).not_to have_received(:write)
      end

      it "does not cache a value computed exactly at the edge of the window" do
        allow(Rails.cache).to receive(:read).with(cache_key).and_return(nil)

        travel_to(boundary + described_class::SETTLE_WINDOW, with_usec: true) do
          tracking_cache_service_class.new("test", invalidate_if_older_than: boundary).call { new_value }
        end

        expect(Rails.cache).not_to have_received(:write)
      end

      it "caches once the boundary is older than the window" do
        allow(Rails.cache).to receive(:read).with(cache_key).and_return(nil)
        computed_at = boundary + described_class::SETTLE_WINDOW + 1.second

        travel_to(computed_at, with_usec: true) do
          tracking_cache_service_class.new("test", invalidate_if_older_than: boundary).call { new_value }
        end

        expect(Rails.cache).to have_received(:write).with(
          cache_key,
          {"cached_at" => boundary.iso8601(6), "value" => new_value},
          expires_in: nil
        )
      end

      it "measures the window from before the block, so a slow aggregation cannot fake a settled boundary" do
        allow(Rails.cache).to receive(:read).with(cache_key).and_return(nil)
        started_at = boundary + 0.4.seconds

        travel_to(started_at, with_usec: true) do
          tracking_cache_service_class.new("test", invalidate_if_older_than: boundary).call do
            travel_to(started_at + 30.seconds, with_usec: true)
            new_value
          end
        end

        expect(Rails.cache).not_to have_received(:write)
      end

      it "caches when no last seen event timestamp is given" do
        allow(Rails.cache).to receive(:read).with(cache_key).and_return(nil)

        tracking_cache_service_class.new("test").call { new_value }

        expect(Rails.cache).to have_received(:write)
      end

      it "does not gate services that do not track the creation time" do
        service = test_cache_service_class.new("untracked")
        allow(Rails.cache).to receive(:read).with(service.cache_key).and_return(nil)

        service.call { new_value }

        expect(Rails.cache).to have_received(:write).with(service.cache_key, new_value, expires_in: nil)
      end

      # End-to-end guard for the reported bug, and the example that fails without the settle gate.
      #
      # Production trace: events enriched at 05:31:13 and 05:31:15, usage aggregated at 05:31:15.4
      # between two inserts that both floor to 05:31:15, so it counts only some of them. Without the
      # gate the partial value is cached under cached_at = 05:31:15; the sibling never moves
      # MAX(enriched_at), 05:31:15 >= 05:31:15 holds on every later read, and the partial usage is
      # served until the entry expires at the end of the billing period.
      it "does not serve a partial usage computed while the boundary was unsettled" do
        newest_event = Time.zone.parse("2026-07-27T05:31:15.000Z")

        partial = write_entry(
          computed_at: newest_event + 0.4.seconds,
          invalidate_if_older_than: newest_event,
          value: "partial-usage"
        )
        expect(partial).to be_nil

        result, block_called = read_entry(partial, invalidate_if_older_than: newest_event)

        expect(block_called).to be true
        expect(result).to eq("recomputed")
      end
    end

    describe "invalidation" do
      it "recomputes when an event was enriched while the block was computing" do
        computed_at = Time.zone.parse("2026-07-27T10:00:00.500Z")
        enriched_mid_compute = computed_at + 2.seconds

        wrapped = write_entry(computed_at:, invalidate_if_older_than: computed_at - 3.hours)
        result, block_called = read_entry(wrapped, invalidate_if_older_than: enriched_mid_compute)

        expect(block_called).to be true
        expect(result).to eq("recomputed")
      end

      # Regression guard. An event inserted *after* the aggregation can carry an *earlier*
      # enriched_at, because ClickHouse fills it with now(), which floors to the second. Stamping
      # cached_at with a wall clock reading compares a precise time against a floored one, treats
      # that event as already covered, and pins the entry for the rest of the billing period.
      # The stamp must stay the last seen event timestamp for this to invalidate.
      it "recomputes when an event landing after the aggregation floors to an earlier second" do
        last_seen_at = Time.zone.parse("2026-07-27T05:30:00.000Z")
        computed_at = Time.zone.parse("2026-07-27T05:31:15.400Z")
        # inserted at 05:31:15.6, recorded as 05:31:15.000 - before the computation
        floored_enriched_at = Time.zone.parse("2026-07-27T05:31:15.000Z")

        wrapped = write_entry(computed_at:, invalidate_if_older_than: last_seen_at)
        result, block_called = read_entry(wrapped, invalidate_if_older_than: floored_enriched_at)

        expect(block_called).to be true
        expect(result).to eq("recomputed")
      end

      it "serves the cached value on a re-read for the same last seen event" do
        last_seen_at = Time.zone.parse("2026-07-27T10:00:00.123Z")

        wrapped = write_entry(computed_at: last_seen_at + 10.seconds, invalidate_if_older_than: last_seen_at)
        result, block_called = read_entry(wrapped, invalidate_if_older_than: last_seen_at)

        expect(result).to eq("new_value")
        expect(block_called).to be false
      end

      it "keeps serving the cached value across repeated usage queries" do
        last_seen_at = Time.zone.parse("2026-07-27T10:00:00.123Z")
        wrapped = write_entry(computed_at: last_seen_at + 10.seconds, invalidate_if_older_than: last_seen_at)

        blocks_called = Array.new(3) do
          _result, block_called = read_entry(wrapped, invalidate_if_older_than: last_seen_at)
          block_called
        end

        expect(blocks_called).to all(be false)
      end

      it "serves the cached value for a recurring charge seeded with the period start" do
        # Recurring charges without in-period events are seeded with boundaries.charges_from_datetime,
        # a constant for the whole period, so they must still benefit from the cache.
        period_start = Time.zone.parse("2026-07-01T00:00:00.000Z")

        wrapped = write_entry(computed_at: period_start + 5.days, invalidate_if_older_than: period_start)
        result, block_called = read_entry(wrapped, invalidate_if_older_than: period_start)

        expect(result).to eq("new_value")
        expect(block_called).to be false
      end
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

    context "when the wrapped value has no cached_at" do
      before { allow(Rails.cache).to receive(:read).with(cache_key).and_return({"value" => "cached_value"}) }

      it "recomputes rather than assuming the entry is fresh" do
        service = tracking_cache_service_class.new("test", invalidate_if_older_than: 1.hour.ago)

        result = service.call { new_value }

        expect(result).to eq(new_value)
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
