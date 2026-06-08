# frozen_string_literal: true

require "rails_helper"
require "lago/redis_loading_retry_middleware"

RSpec.describe Lago::RedisLoadingRetryMiddleware do
  let(:middleware) { middleware_class.new(nil) }

  let(:middleware_class) do
    Class.new(RedisClient::BasicMiddleware) { include Lago::RedisLoadingRetryMiddleware }
  end

  let(:retry_attempts) { [0.1, 0.2, 0.3] }
  let(:config) { RedisClient::Config.new(custom: {loading_retry_attempts: retry_attempts}) }
  let(:command) { ["LPUSH", "queue", "job"] }
  let(:loading_error) { RedisClient::CommandError.parse("LOADING Redis is loading the dataset in memory") }

  before do
    allow(middleware).to receive(:sleep)
    allow(Rails.logger).to receive(:warn)
  end

  describe "#call" do
    context "when the command succeeds" do
      it "returns the result without retrying" do
        result = middleware.call(command, config) { "OK" }

        expect(result).to eq("OK")
        expect(middleware).not_to have_received(:sleep)
      end
    end

    context "when the command raises a LOADING error then succeeds" do
      it "retries on the backoff schedule and returns the result" do
        attempts = 0
        result = middleware.call(command, config) do
          attempts += 1
          raise loading_error if attempts < 3

          "OK"
        end

        expect(result).to eq("OK")
        expect(attempts).to eq(3)
        expect(middleware).to have_received(:sleep).with(0.1)
        expect(middleware).to have_received(:sleep).with(0.2)
      end

      it "logs a warning before each retry" do
        attempts = 0
        middleware.call(command, config) do
          attempts += 1
          raise loading_error if attempts < 3

          "OK"
        end

        expect(Rails.logger).to have_received(:warn).with(/retrying in 0.1s \(attempt 1\/3\)/)
        expect(Rails.logger).to have_received(:warn).with(/retrying in 0.2s \(attempt 2\/3\)/)
      end
    end

    context "when the LOADING error outlasts the schedule" do
      it "sleeps once per interval then re-raises" do
        expect do
          middleware.call(command, config) { raise loading_error }
        end.to raise_error(RedisClient::CommandError, /LOADING/)

        expect(middleware).to have_received(:sleep).exactly(3).times
      end
    end

    context "when the error is not a LOADING error" do
      let(:other_error) { RedisClient::CommandError.parse("ERR unknown command") }

      it "re-raises immediately without retrying" do
        attempts = 0

        expect do
          middleware.call(command, config) do
            attempts += 1
            raise other_error
          end
        end.to raise_error(RedisClient::CommandError, /ERR/)

        expect(attempts).to eq(1)
        expect(middleware).not_to have_received(:sleep)
      end
    end

    context "when the schedule is empty" do
      let(:retry_attempts) { [] }

      it "re-raises the LOADING error without retrying" do
        attempts = 0

        expect do
          middleware.call(command, config) do
            attempts += 1
            raise loading_error
          end
        end.to raise_error(RedisClient::CommandError, /LOADING/)

        expect(attempts).to eq(1)
        expect(middleware).not_to have_received(:sleep)
      end
    end

    context "when no schedule is configured" do
      let(:config) { RedisClient::Config.new }

      it "re-raises the LOADING error without retrying" do
        expect do
          middleware.call(command, config) { raise loading_error }
        end.to raise_error(RedisClient::CommandError, /LOADING/)

        expect(middleware).not_to have_received(:sleep)
      end
    end
  end

  describe "#call_pipelined" do
    it "retries LOADING errors like #call" do
      attempts = 0
      result = middleware.call_pipelined([command], config) do
        attempts += 1
        raise loading_error if attempts < 2

        ["OK"]
      end

      expect(result).to eq(["OK"])
      expect(middleware).to have_received(:sleep).with(0.1)
    end
  end
end
