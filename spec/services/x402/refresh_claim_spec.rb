# frozen_string_literal: true

require "rails_helper"

describe X402::RefreshClaim, cache: :redis do
  let(:customer) { create(:customer) }
  let(:wallet) { create(:wallet, customer:, x402_enabled: true) }
  let(:claim_key) { "x402:refreshing:#{customer.id}" }
  let(:counter_key) { "x402:reserved:#{wallet.id}" }
  let(:unreachable_store) { ActiveSupport::Cache::RedisCacheStore.new(url: "redis://localhost:1") }
  let(:extra) { {organization_id: customer.organization_id, customer_id: customer.id} }

  before { allow(Sentry).to receive(:capture_exception) }

  def losing_first_reply(hook)
    lost = false

    Module.new do
      define_method(hook) do |commands, config, &block|
        result = super(commands, config, &block)

        if !lost && yield(commands)
          lost = true
          raise RedisClient::ReadTimeoutError, "reply lost"
        end

        result
      end
    end
  end

  describe ".acquire" do
    subject(:claim) { described_class.acquire(customer) }

    it "returns a claim" do
      expect(claim).to be_a(described_class)
    end

    it "stores a token under the claim key for five minutes" do
      claim

      expect(Rails.cache.redis.then { it.pttl(claim_key) }).to be_between(299_000, 300_000)
    end

    context "when another refresh holds the claim" do
      before { Rails.cache.redis.then { it.set(claim_key, "other", ex: 300) } }

      it "returns nil" do
        expect(claim).to be_nil
      end

      it "leaves the claim alone" do
        claim

        expect(Rails.cache.redis.then { it.get(claim_key) }).to eq("other")
      end
    end

    context "when the SET reply is lost" do
      let(:lossy_client) do
        Redis.new(url: ENV.fetch("REDIS_URL"), middlewares: [losing_first_reply(:call) { |command| command.first.to_s.casecmp?("set") }])
      end

      before { allow(X402::ReservationCounter).to receive(:redis).and_return(lossy_client) }

      it "returns a claim" do
        expect(claim).to be_a(described_class)
      end

      it "holds a token under the claim key" do
        claim

        expect(Rails.cache.redis.then { it.get(claim_key) }).to be_present
      end
    end

    context "with a cache store other than Redis" do
      before { allow(Rails).to receive(:cache).and_return(ActiveSupport::Cache::MemoryStore.new) }

      it "returns nil" do
        expect(claim).to be_nil
      end

      it "reports the failure" do
        claim

        expect(Sentry).to have_received(:capture_exception).with(
          an_instance_of(X402::ReservationCounter::UnavailableError),
          extra:
        )
      end
    end

    context "when Redis is unreachable" do
      before { allow(Rails).to receive(:cache).and_return(unreachable_store) }

      it "returns nil" do
        expect(claim).to be_nil
      end

      it "reports the failure" do
        claim

        expect(Sentry).to have_received(:capture_exception).with(an_instance_of(Redis::CannotConnectError), extra:)
      end
    end
  end

  describe "#release" do
    subject(:release) { claim.release({wallet => 30}) }

    let(:claim) { described_class.acquire(customer) }
    let(:counter) { Rails.cache.read(counter_key, raw: true) }

    context "with a reservation" do
      before { Rails.cache.redis.then { it.set(counter_key, 30, ex: 3600) } }

      it "lowers the counter" do
        release

        expect(counter).to eq("0")
      end

      it "frees the claim" do
        release

        expect(Rails.cache.redis.then { it.exists?(claim_key) }).to be(false)
      end
    end

    context "with a counter about to expire" do
      before { Rails.cache.redis.then { it.set(counter_key, 30, ex: 60) } }

      it "re-arms the TTL to one hour" do
        release

        expect(Rails.cache.redis.then { it.ttl(counter_key) }).to be_between(3500, 3600)
      end
    end

    context "when the EXEC reply is lost" do
      let(:lossy_client) do
        Redis.new(url: ENV.fetch("REDIS_URL"), middlewares: [losing_first_reply(:call_pipelined) { |commands| commands.last.first.to_s.casecmp?("exec") }])
      end

      before do
        Rails.cache.redis.then { it.set(counter_key, 30, ex: 3600) }
        claim
        allow(X402::ReservationCounter).to receive(:redis).and_return(lossy_client)
      end

      it "releases the counter exactly once" do
        release

        expect(counter).to eq("0")
      end

      it "reports the failure" do
        release

        expect(Sentry).to have_received(:capture_exception).with(an_instance_of(Redis::TimeoutError), extra:)
      end
    end

    context "without a counter" do
      subject(:release) { claim.release({wallet => 5}) }

      it "goes negative" do
        release

        expect(counter).to eq("-5")
      end

      it "arms a TTL of one hour" do
        release

        expect(Rails.cache.redis.then { it.ttl(counter_key) }).to be_between(3500, 3600)
      end
    end

    context "when another refresh took the claim" do
      before do
        Rails.cache.redis.then { it.set(counter_key, 30, ex: 3600) }
        claim
        Rails.cache.redis.then { it.set(claim_key, "other") }
      end

      it "leaves the counter alone" do
        release

        expect(counter).to eq("30")
      end

      it "leaves the other claim alone" do
        release

        expect(Rails.cache.redis.then { it.get(claim_key) }).to eq("other")
      end

      it "leaves no WATCH on the connection" do
        release

        result = Rails.cache.redis.then do |client|
          client.set(claim_key, "x")
          client.multi { |transaction| transaction.set("x402:probe:#{customer.id}", 1) }
        end

        expect(result).not_to be_nil
      end
    end

    context "when Redis is unreachable" do
      before do
        claim
        allow(Rails).to receive(:cache).and_return(unreachable_store)
      end

      it "returns nil" do
        expect(release).to be_nil
      end

      it "reports the failure" do
        release

        expect(Sentry).to have_received(:capture_exception).with(an_instance_of(Redis::CannotConnectError), extra:)
      end
    end
  end

  describe "#drop" do
    subject(:drop) { claim.drop }

    let(:claim) { described_class.acquire(customer) }

    it "deletes the claim key" do
      drop

      expect(Rails.cache.redis.then { it.exists?(claim_key) }).to be(false)
    end

    context "when another refresh took the claim" do
      before do
        claim
        Rails.cache.redis.then { it.set(claim_key, "other") }
      end

      it "leaves the other claim alone" do
        drop

        expect(Rails.cache.redis.then { it.get(claim_key) }).to eq("other")
      end
    end
  end
end
