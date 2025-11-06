# frozen_string_literal: true

require "rails_helper"

RSpec.describe Redlock::ClientPatch do
  subject(:lock_manager) { Redlock::Client.new([redis_client]) }

  let(:redis_url) { ENV["REDIS_URL"] }
  let(:redis_client) do
    redis_wrapper_class.new(RedisClient.new(url: redis_url))
  end
  let(:redis_wrapper_class) do
    Class.new(SimpleDelegator) do
      attr_reader :lock_attempts

      def initialize(*args, **kwargs)
        super
        @lock_attempts = []
      end

      def reset_lock_attempts
        @lock_attempts = []
      end

      def call(*args, **kwargs)
        if args.first == "EVALSHA" && args[1] == Redlock::Scripts::LOCK_SCRIPT_SHA
          @lock_attempts << Time.zone.now
        end
        super
      end
    end
  end

  let(:resource) { "test_resource_#{SecureRandom.hex(8)}" }
  let(:ttl) { 10000 }
  let(:options) { {retry_count: 0} }

  describe "#lock" do
    it "locks the resource" do
      lock_info = lock_manager.lock(resource, ttl, options)

      expect(lock_info).to match({validity: a_kind_of(Integer), resource: resource, value: a_kind_of(String)})

      lock_info2 = lock_manager.lock(resource, ttl, options)
      expect(lock_info2).to be false

      lock_manager.unlock(lock_info)

      lock_info3 = lock_manager.lock(resource, ttl, options)
      expect(lock_info3).to match({validity: a_kind_of(Integer), resource: resource, value: a_kind_of(String)})
    end

    context "when lock acquisition fails" do
      before do
        lock_manager.lock(resource, ttl, options)
        redis_client.reset_lock_attempts
      end

      it "does not retry" do
        expect(lock_manager.lock(resource, ttl, options)).to be false
        expect(redis_client.lock_attempts.length).to eq 1
      end

      context "when lock retry options is defined" do
        it "retries to acquire the lock" do
          expect(lock_manager.lock(resource, ttl, {retry_count: 3})).to be false

          expect(redis_client.lock_attempts.length).to eq 4
          3.times do |i|
            expect(redis_client.lock_attempts[i + 1]).to be >= (redis_client.lock_attempts[i] + 0.2.seconds)
          end
        end
      end
    end

    context "when connection to redis is lost" do
      let(:redis_url) { "redis://localhost:22222" }

      it "retries to acquire the lock" do
        expect do
          lock_manager.lock(resource, ttl, options)
        end.to raise_error(Redlock::LockAcquisitionError)

        expect(redis_client.lock_attempts.length).to eq 4
        3.times do |i|
          expect(redis_client.lock_attempts[i + 1]).to be >= (redis_client.lock_attempts[i] + 0.2.seconds)
        end
      end
    end
  end
end
