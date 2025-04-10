# frozen_string_literal: true

require "rails_helper"

RSpec.describe Subscriptions::ConsumeSubscriptionRefreshedQueueService do
  subject(:flag_service) { described_class.new }

  let(:redis_client) { instance_double(Redis) }

  let(:values) { ["#{SecureRandom.uuid}:#{SecureRandom.uuid}", "#{SecureRandom.uuid}:#{SecureRandom.uuid}"] }
  let(:loop_values) { [values, []] }

  let(:redis_url) { "localhost:6379" }

  before do
    allow(Redis).to receive(:new).and_return(redis_client)
    allow(redis_client).to receive(:srandmember)
      .with(described_class::REDIS_STORE_NAME, described_class::BATCH_SIZE)
      .and_return(*loop_values)

    allow(redis_client).to receive(:srem)

    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with("LAGO_REDIS_STORE_URL").and_return(redis_url)
  end

  describe "#call" do
    it "flags all subscriptions as refreshed" do
      result = flag_service.call

      expect(result).to be_success
      expect(Subscriptions::FlagRefreshedJob).to have_been_enqueued.twice
    end

    context "with multiple batches" do
      let(:loop_values) { [values, values, []] }

      it "flags all subscriptions as refreshed" do
        result = flag_service.call

        expect(result).to be_success
        expect(Subscriptions::FlagRefreshedJob).to have_been_enqueued.exactly(4).times
      end
    end

    context "with no subscriptions" do
      let(:loop_values) { [[]] }

      it "does not flag any subscriptions as refreshed" do
        result = flag_service.call

        expect(result).to be_success
        expect(Subscriptions::FlagRefreshedJob).not_to have_been_enqueued
      end
    end

    context "when timeout is reached" do
      let(:start_time) { Time.current }

      before do
        allow(Time).to receive(:current).and_return(
          start_time,
          start_time + described_class::PROCESSING_TIMEOUT + 1.second
        )
      end

      it "flags all subscriptions as refreshed" do
        result = flag_service.call

        expect(result).to be_success
        expect(Subscriptions::FlagRefreshedJob).not_to have_been_enqueued
      end
    end

    context "when the redis env var is not present" do
      let(:redis_url) { nil }

      it "does not flag any subscriptions as refreshed" do
        result = flag_service.call

        expect(result).to be_success
        expect(Subscriptions::FlagRefreshedJob).not_to have_been_enqueued
      end
    end
  end
end
