# frozen_string_literal: true

require "rails_helper"

describe X402::ReservationCounter, cache: :redis do
  subject(:counter) { described_class.new(wallet) }

  let(:wallet) { create(:wallet) }
  let(:key) { "x402:reserved:#{wallet.id}" }
  let(:unreachable_store) { ActiveSupport::Cache::RedisCacheStore.new(url: "redis://localhost:1") }

  before { allow(Sentry).to receive(:capture_exception) }

  describe ".enabled?" do
    subject(:enabled) { described_class.enabled?(organization) }

    let(:organization) { build(:organization) }

    it { is_expected.to be(true) }

    context "with the opt-out flag" do
      let(:organization) { build(:organization, feature_flags: ["x402_reservation_counter_disabled"]) }

      it { is_expected.to be(false) }
    end
  end

  describe "#reserve" do
    subject(:reserve) { counter.reserve(3) }

    let(:ttl) { Rails.cache.redis.then { it.ttl(key) } }

    context "with an existing reservation" do
      before { Rails.cache.redis.then { it.incrby(key, 5) } }

      it "returns the running total" do
        expect(reserve).to eq(8)
      end
    end

    context "without an existing reservation" do
      before { reserve }

      it "arms a TTL of one hour" do
        expect(ttl).to be_between(3500, 3600)
      end
    end

    context "with a key about to expire" do
      before do
        Rails.cache.redis.then { it.set(key, 5, ex: 60) }
        reserve
      end

      it "re-arms the TTL" do
        expect(ttl).to be_between(3500, 3600)
      end
    end

    context "with a cache store that is not Redis" do
      before { allow(Rails).to receive(:cache).and_return(ActiveSupport::Cache::MemoryStore.new) }

      it "returns nil" do
        expect(reserve).to be_nil
      end

      it "reports the failure" do
        reserve

        expect(Sentry).to have_received(:capture_exception).with(
          an_instance_of(described_class::UnavailableError),
          extra: {organization_id: wallet.organization_id, wallet_id: wallet.id}
        )
      end
    end

    context "with an unreachable Redis" do
      before { allow(Rails).to receive(:cache).and_return(unreachable_store) }

      it "returns nil" do
        expect(reserve).to be_nil
      end

      it "reports the failure" do
        reserve

        expect(Sentry).to have_received(:capture_exception).with(
          an_instance_of(Redis::CannotConnectError),
          extra: {organization_id: wallet.organization_id, wallet_id: wallet.id}
        )
      end
    end

    context "with a marshalled value under the key" do
      before { Rails.cache.write(key, 5) }

      it "returns nil" do
        expect(reserve).to be_nil
      end

      it "reports the failure" do
        reserve

        expect(Sentry).to have_received(:capture_exception).with(
          an_instance_of(Redis::CommandError),
          extra: {organization_id: wallet.organization_id, wallet_id: wallet.id}
        )
      end
    end
  end

  describe "#capture" do
    subject(:capture) { counter.capture }

    context "with a reservation" do
      before { counter.reserve(4) }

      it "returns what reserve wrote" do
        expect(capture).to eq(4)
      end
    end

    context "without a reservation" do
      it "returns zero" do
        expect(capture).to eq(0)
      end
    end
  end

  describe "#release" do
    subject(:release) { counter.release(5) }

    let(:ttl) { Rails.cache.redis.then { it.ttl(key) } }

    context "with a key about to expire" do
      before { Rails.cache.redis.then { it.set(key, 7, ex: 60) } }

      it "lowers the reservation" do
        release

        expect(counter.capture).to eq(2)
      end

      it "does not reset the TTL" do
        release

        expect(ttl).to be_between(1, 60)
      end
    end

    context "without a key" do
      before { release }

      it "goes negative" do
        expect(counter.capture).to eq(-5)
      end

      it "arms a TTL of one hour" do
        expect(ttl).to be_between(3500, 3600)
      end
    end

    context "with an unreachable Redis" do
      before { allow(Rails).to receive(:cache).and_return(unreachable_store) }

      it "returns nil without raising" do
        expect(release).to be_nil
      end
    end
  end
end
