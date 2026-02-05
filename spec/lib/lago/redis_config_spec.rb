# frozen_string_literal: true

require "rails_helper"

RSpec.describe Lago::RedisConfig do
  around do |example|
    # Clear all Redis-related env vars before each test
    original_env = ENV.to_h.slice(
      "REDIS_URL", "REDIS_PASSWORD", "REDIS_SENTINELS", "REDIS_MASTER_NAME",
      "REDIS_SENTINEL_USERNAME", "REDIS_SENTINEL_PASSWORD",
      "LAGO_REDIS_CACHE_URL", "LAGO_REDIS_CACHE_PASSWORD", "LAGO_REDIS_CACHE_SENTINELS", "LAGO_REDIS_CACHE_MASTER_NAME",
      "LAGO_REDIS_CACHE_SENTINEL_USERNAME", "LAGO_REDIS_CACHE_SENTINEL_PASSWORD",
      "LAGO_REDIS_STORE_URL", "LAGO_REDIS_STORE_PASSWORD", "LAGO_REDIS_STORE_SENTINELS", "LAGO_REDIS_STORE_MASTER_NAME",
      "LAGO_REDIS_STORE_SENTINEL_USERNAME", "LAGO_REDIS_STORE_SENTINEL_PASSWORD",
      "LAGO_REDIS_STORE_DB", "LAGO_REDIS_STORE_SSL", "LAGO_REDIS_STORE_DISABLE_SSL_VERIFY"
    )

    # Clear env vars
    original_env.keys.each { |key| ENV.delete(key) }

    example.run
  ensure
    # Restore original values
    original_env.each { |key, value| ENV[key] = value }
  end

  describe ".build" do
    context "with main instance" do
      context "when standalone mode with URL only" do
        before { ENV["REDIS_URL"] = "redis://localhost:6379" }

        it "returns standalone configuration" do
          config = described_class.build(:main)

          expect(config).to include(
            url: "redis://localhost:6379",
            timeout: 5,
            reconnect_attempts: 3,
            ssl_params: {verify_mode: OpenSSL::SSL::VERIFY_NONE}
          )
          expect(config).not_to have_key(:password)
          expect(config).not_to have_key(:sentinels)
        end
      end

      context "when standalone mode with password" do
        before do
          ENV["REDIS_URL"] = "redis://localhost:6379"
          ENV["REDIS_PASSWORD"] = "secret123"
        end

        it "includes password in configuration" do
          config = described_class.build(:main)

          expect(config).to include(
            url: "redis://localhost:6379",
            password: "secret123"
          )
        end
      end

      context "when password is empty string" do
        before do
          ENV["REDIS_URL"] = "redis://localhost:6379"
          ENV["REDIS_PASSWORD"] = ""
        end

        it "does not include password" do
          config = described_class.build(:main)

          expect(config).not_to have_key(:password)
        end
      end

      context "when sentinel mode" do
        before do
          ENV["REDIS_SENTINELS"] = "sentinel1:26379,sentinel2:26379,sentinel3:26379"
          ENV["REDIS_MASTER_NAME"] = "myredis"
        end

        it "returns sentinel configuration" do
          config = described_class.build(:main)

          expect(config).to include(
            url: nil,
            name: "myredis",
            role: :master,
            timeout: 5,
            reconnect_attempts: 3
          )
          expect(config[:sentinels]).to eq([
            {host: "sentinel1", port: 26379},
            {host: "sentinel2", port: 26379},
            {host: "sentinel3", port: 26379}
          ])
        end
      end

      context "when sentinel mode without explicit master name" do
        before do
          ENV["REDIS_SENTINELS"] = "sentinel1:26379"
        end

        it "uses default master name" do
          config = described_class.build(:main)

          expect(config[:name]).to eq("mymaster")
        end
      end

      context "when sentinel mode without explicit port" do
        before do
          ENV["REDIS_SENTINELS"] = "sentinel1,sentinel2"
        end

        it "uses default sentinel port" do
          config = described_class.build(:main)

          expect(config[:sentinels]).to eq([
            {host: "sentinel1", port: 26379},
            {host: "sentinel2", port: 26379}
          ])
        end
      end

      context "when sentinel mode with password" do
        before do
          ENV["REDIS_SENTINELS"] = "sentinel1:26379"
          ENV["REDIS_PASSWORD"] = "secret123"
        end

        it "includes password in configuration" do
          config = described_class.build(:main)

          expect(config).to include(password: "secret123")
        end
      end

      context "when sentinel mode with sentinel authentication" do
        before do
          ENV["REDIS_SENTINELS"] = "sentinel1:26379"
          ENV["REDIS_SENTINEL_USERNAME"] = "sentinel_user"
          ENV["REDIS_SENTINEL_PASSWORD"] = "sentinel_pass"
        end

        it "includes sentinel credentials in configuration" do
          config = described_class.build(:main)

          expect(config).to include(
            sentinel_username: "sentinel_user",
            sentinel_password: "sentinel_pass"
          )
        end
      end

      context "when sentinel mode with empty sentinel credentials" do
        before do
          ENV["REDIS_SENTINELS"] = "sentinel1:26379"
          ENV["REDIS_SENTINEL_USERNAME"] = ""
          ENV["REDIS_SENTINEL_PASSWORD"] = ""
        end

        it "does not include sentinel credentials" do
          config = described_class.build(:main)

          expect(config).not_to have_key(:sentinel_username)
          expect(config).not_to have_key(:sentinel_password)
        end
      end

      context "when no configuration is set" do
        it "returns empty hash" do
          config = described_class.build(:main)

          expect(config).to eq({})
        end
      end
    end

    context "with cache instance" do
      context "when standalone mode" do
        before { ENV["LAGO_REDIS_CACHE_URL"] = "redis://cache.example.com:6379" }

        it "returns standalone configuration" do
          config = described_class.build(:cache)

          expect(config).to include(
            url: "redis://cache.example.com:6379",
            timeout: 5,
            ssl_params: {verify_mode: OpenSSL::SSL::VERIFY_NONE}
          )
        end
      end

      context "when sentinel mode" do
        before do
          ENV["LAGO_REDIS_CACHE_SENTINELS"] = "cache-sentinel1:26379,cache-sentinel2:26379"
          ENV["LAGO_REDIS_CACHE_MASTER_NAME"] = "cache-master"
          ENV["LAGO_REDIS_CACHE_PASSWORD"] = "cache-pass"
        end

        it "returns sentinel configuration" do
          config = described_class.build(:cache)

          expect(config).to include(
            name: "cache-master",
            password: "cache-pass",
            role: :master
          )
          expect(config[:sentinels]).to eq([
            {host: "cache-sentinel1", port: 26379},
            {host: "cache-sentinel2", port: 26379}
          ])
        end
      end
    end

    context "with store instance" do
      context "when standalone mode with URL prefix" do
        before { ENV["LAGO_REDIS_STORE_URL"] = "redis://store.example.com:6379" }

        it "returns standalone configuration" do
          config = described_class.build(:store)

          expect(config).to include(url: "redis://store.example.com:6379")
          expect(config).not_to have_key(:ssl_params)
          expect(config).not_to have_key(:ssl)
        end
      end

      context "when standalone mode without URL prefix" do
        before { ENV["LAGO_REDIS_STORE_URL"] = "store.example.com:6379" }

        it "normalizes URL with redis:// prefix" do
          config = described_class.build(:store)

          expect(config[:url]).to eq("redis://store.example.com:6379")
        end
      end

      context "when SSL is enabled via environment variable" do
        before do
          ENV["LAGO_REDIS_STORE_URL"] = "redis://store.example.com:6379"
          ENV["LAGO_REDIS_STORE_SSL"] = "true"
        end

        it "enables SSL" do
          config = described_class.build(:store)

          expect(config[:ssl]).to be true
        end
      end

      context "when SSL is enabled via rediss:// URL" do
        before { ENV["LAGO_REDIS_STORE_URL"] = "rediss://store.example.com:6379" }

        it "enables SSL" do
          config = described_class.build(:store)

          expect(config[:ssl]).to be true
        end
      end

      context "when SSL verify is disabled" do
        before do
          ENV["LAGO_REDIS_STORE_URL"] = "redis://store.example.com:6379"
          ENV["LAGO_REDIS_STORE_SSL"] = "true"
          ENV["LAGO_REDIS_STORE_DISABLE_SSL_VERIFY"] = "true"
        end

        it "disables SSL verification" do
          config = described_class.build(:store)

          expect(config[:ssl_params]).to eq({verify_mode: OpenSSL::SSL::VERIFY_NONE})
        end
      end

      context "when database is specified" do
        before do
          ENV["LAGO_REDIS_STORE_URL"] = "redis://store.example.com:6379"
          ENV["LAGO_REDIS_STORE_DB"] = "5"
        end

        it "includes database in configuration" do
          config = described_class.build(:store)

          expect(config[:db]).to eq(5)
        end
      end

      context "when sentinel mode" do
        before do
          ENV["LAGO_REDIS_STORE_SENTINELS"] = "store-sentinel1:26379"
          ENV["LAGO_REDIS_STORE_MASTER_NAME"] = "store-master"
          ENV["LAGO_REDIS_STORE_PASSWORD"] = "store-pass"
          ENV["LAGO_REDIS_STORE_DB"] = "2"
        end

        it "returns sentinel configuration with store-specific options" do
          config = described_class.build(:store)

          expect(config).to include(
            name: "store-master",
            password: "store-pass",
            db: 2,
            role: :master
          )
        end
      end
    end

    context "with invalid instance" do
      it "raises KeyError" do
        expect { described_class.build(:invalid) }.to raise_error(KeyError)
      end
    end
  end

  describe ".url" do
    context "when URL is set" do
      before { ENV["REDIS_URL"] = "redis://localhost:6379" }

      it "returns the URL" do
        expect(described_class.url(:main)).to eq("redis://localhost:6379")
      end
    end

    context "when URL is not set" do
      it "returns nil" do
        expect(described_class.url(:main)).to be_nil
      end
    end

    context "with cache instance" do
      before { ENV["LAGO_REDIS_CACHE_URL"] = "redis://cache:6379" }

      it "returns the cache URL" do
        expect(described_class.url(:cache)).to eq("redis://cache:6379")
      end
    end
  end

  describe ".configured?" do
    context "when URL is set" do
      before { ENV["REDIS_URL"] = "redis://localhost:6379" }

      it "returns true" do
        expect(described_class.configured?(:main)).to be true
      end
    end

    context "when sentinels are set" do
      before { ENV["REDIS_SENTINELS"] = "sentinel1:26379" }

      it "returns true" do
        expect(described_class.configured?(:main)).to be true
      end
    end

    context "when nothing is set" do
      it "returns false" do
        expect(described_class.configured?(:main)).to be false
      end
    end
  end
end
