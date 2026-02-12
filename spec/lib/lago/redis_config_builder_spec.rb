# frozen_string_literal: true

require "rails_helper"
require "lago/redis_config_builder"

RSpec.describe Lago::RedisConfigBuilder do
  subject(:builder) { described_class.new }

  describe "#sidekiq" do
    subject(:result) { builder.sidekiq }

    context "with no environment variables set" do
      before do
        ENV.delete("REDIS_URL")
        ENV.delete("REDIS_PASSWORD")
        ENV.delete("LAGO_REDIS_SIDEKIQ_SENTINELS")
      end

      it "returns base config" do
        expect(result).to eq(
          ssl_params: {verify_mode: OpenSSL::SSL::VERIFY_NONE}
        )
      end
    end

    context "with REDIS_URL set" do
      before do
        ENV["REDIS_URL"] = "redis://localhost:6379"
        ENV.delete("REDIS_PASSWORD")
        ENV.delete("LAGO_REDIS_SIDEKIQ_SENTINELS")
      end

      after { ENV.delete("REDIS_URL") }

      it "includes the url" do
        expect(result).to include(url: "redis://localhost:6379")
      end
    end

    context "with REDIS_PASSWORD set" do
      before do
        ENV.delete("REDIS_URL")
        ENV["REDIS_PASSWORD"] = "secret"
        ENV.delete("LAGO_REDIS_SIDEKIQ_SENTINELS")
      end

      after { ENV.delete("REDIS_PASSWORD") }

      it "includes the password" do
        expect(result).to include(password: "secret")
      end
    end

    context "with REDIS_PASSWORD empty" do
      before do
        ENV.delete("REDIS_URL")
        ENV["REDIS_PASSWORD"] = ""
        ENV.delete("LAGO_REDIS_SIDEKIQ_SENTINELS")
      end

      after { ENV.delete("REDIS_PASSWORD") }

      it "does not include the password" do
        expect(result).not_to have_key(:password)
      end
    end

    context "with sentinels configured" do
      before do
        ENV.delete("REDIS_URL")
        ENV.delete("REDIS_PASSWORD")
        ENV["LAGO_REDIS_SIDEKIQ_SENTINELS"] = "sentinel1:26379,sentinel2:26380"
      end

      after do
        ENV.delete("LAGO_REDIS_SIDEKIQ_SENTINELS")
        ENV.delete("LAGO_REDIS_SIDEKIQ_MASTER_NAME")
      end

      it "includes sentinel config with default master name" do
        expect(result).to include(
          sentinels: [{host: "sentinel1", port: 26379}, {host: "sentinel2", port: 26380}],
          role: :master,
          name: "master"
        )
      end

      context "with custom master name" do
        before { ENV["LAGO_REDIS_SIDEKIQ_MASTER_NAME"] = "mymaster" }

        after { ENV.delete("LAGO_REDIS_SIDEKIQ_MASTER_NAME") }

        it "uses the custom master name" do
          expect(result).to include(name: "mymaster")
        end
      end

      context "with sentinel without port" do
        before { ENV["LAGO_REDIS_SIDEKIQ_SENTINELS"] = "sentinel1" }

        it "parses sentinel without port" do
          expect(result[:sentinels]).to eq([{host: "sentinel1"}])
        end
      end
    end

    context "with sentinels and REDIS_URL set" do
      before do
        ENV["REDIS_URL"] = "redis://localhost:6379"
        ENV["LAGO_REDIS_SIDEKIQ_SENTINELS"] = "sentinel1:26379"
        ENV.delete("REDIS_PASSWORD")
      end

      after do
        ENV.delete("REDIS_URL")
        ENV.delete("LAGO_REDIS_SIDEKIQ_SENTINELS")
      end

      it "still includes sentinel config" do
        expect(result).to include(:sentinels, :role, :name)
      end
    end

    context "with all options set" do
      before do
        ENV["REDIS_URL"] = "redis://localhost:6379"
        ENV["REDIS_PASSWORD"] = "secret"
        ENV["LAGO_REDIS_SIDEKIQ_SENTINELS"] = "sentinel1:26379"
        ENV["LAGO_REDIS_SIDEKIQ_MASTER_NAME"] = "mymaster"
      end

      after do
        ENV.delete("REDIS_URL")
        ENV.delete("REDIS_PASSWORD")
        ENV.delete("LAGO_REDIS_SIDEKIQ_SENTINELS")
        ENV.delete("LAGO_REDIS_SIDEKIQ_MASTER_NAME")
      end

      it "includes all config options" do
        expect(result).to eq(
          url: "redis://localhost:6379",
          ssl_params: {verify_mode: OpenSSL::SSL::VERIFY_NONE},
          sentinels: [{host: "sentinel1", port: 26379}],
          role: :master,
          name: "mymaster",
          password: "secret"
        )
      end
    end
  end

  describe "#with_options" do
    before do
      ENV.delete("REDIS_URL")
      ENV.delete("REDIS_PASSWORD")
      ENV.delete("LAGO_REDIS_SIDEKIQ_SENTINELS")
    end

    it "merges extra options into the config" do
      result = builder.with_options(reconnect_attempts: 4).sidekiq
      expect(result).to include(reconnect_attempts: 4)
    end

    it "returns self for chaining" do
      expect(builder.with_options(foo: 1)).to eq(builder)
    end

    it "merges multiple calls" do
      result = builder
        .with_options(reconnect_attempts: 4)
        .with_options(custom: "value")
        .sidekiq
      expect(result).to include(reconnect_attempts: 4, custom: "value")
    end

    it "extra options override base config keys" do
      result = builder.with_options(ssl_params: {verify_mode: OpenSSL::SSL::VERIFY_PEER}).sidekiq
      expect(result).to include(ssl_params: {verify_mode: OpenSSL::SSL::VERIFY_PEER})
    end
  end
end
