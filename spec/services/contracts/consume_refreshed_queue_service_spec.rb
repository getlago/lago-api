# frozen_string_literal: true

require "rails_helper"

RSpec.describe Contracts::ConsumeRefreshedQueueService do
  subject(:result) { described_class.call }

  let(:redis_client) { instance_double(Redis) }
  let(:redis_url) { "localhost:6379" }

  let(:organization_id) { SecureRandom.uuid }
  let(:bucket) do
    ((Time.current.to_i - 20) / described_class::CONTRACT_BUCKET_DURATION) * described_class::CONTRACT_BUCKET_DURATION
  end
  let(:values) do
    [
      "#{organization_id}:ctr_1|#{bucket}",
      "#{organization_id}:ctr_2|#{bucket}"
    ]
  end
  let(:loop_values) { [values, []] }

  before do
    allow(Redis).to receive(:new).and_return(redis_client)
    allow(redis_client).to receive(:zrangebyscore).and_return(*loop_values)
    allow(redis_client).to receive(:zrem)

    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with("LAGO_REDIS_STORE_URL").and_return(redis_url)
  end

  it "flags each contract as refreshed" do
    expect(result).to be_success
    expect(Contracts::FlagRefreshedJob).to have_been_enqueued.with(organization_id, "ctr_1")
    expect(Contracts::FlagRefreshedJob).to have_been_enqueued.with(organization_id, "ctr_2")
  end

  it "reads the members older than one bucket" do
    freeze_time do
      threshold = (Time.current - described_class::CONTRACT_BUCKET_DURATION).to_i

      result

      expect(redis_client).to have_received(:zrangebyscore)
        .with("contract_refreshed_v1", "-inf", threshold, limit: [0, described_class::BATCH_SIZE])
        .at_least(:once)
    end
  end

  it "removes the members it read" do
    result

    expect(redis_client).to have_received(:zrem).with("contract_refreshed_v1", values)
  end

  context "when the external id contains a colon and a pipe" do
    let(:values) { ["#{organization_id}:ctr:eu|2026|#{bucket}"] }

    it "keeps the whole external id" do
      expect(result).to be_success
      expect(Contracts::FlagRefreshedJob).to have_been_enqueued.once.with(organization_id, "ctr:eu|2026")
    end
  end

  context "when a member has no external id" do
    let(:values) { ["#{organization_id}|#{bucket}", "#{organization_id}:|#{bucket}", "#{organization_id}:ctr_1|#{bucket}"] }

    it "removes it without flagging anything" do
      expect(result).to be_success
      expect(Contracts::FlagRefreshedJob).to have_been_enqueued.once.with(organization_id, "ctr_1")
      expect(redis_client).to have_received(:zrem).with("contract_refreshed_v1", values)
    end
  end

  context "with multiple batches" do
    let(:loop_values) { [values, values, []] }

    it "flags the contracts of every batch" do
      expect(result).to be_success
      expect(Contracts::FlagRefreshedJob).to have_been_enqueued.exactly(4).times # 2 batches of 2 members
    end
  end

  context "with an empty queue" do
    let(:loop_values) { [[]] }

    it "flags no contract" do
      expect(result).to be_success
      expect(Contracts::FlagRefreshedJob).not_to have_been_enqueued
      expect(redis_client).not_to have_received(:zrem)
    end
  end

  context "when the timeout is reached" do
    let(:start_time) { Time.current }

    before do
      allow(Time).to receive(:current).and_return(
        start_time,
        start_time + described_class::PROCESSING_TIMEOUT + 1.second
      )
    end

    it "stops reading the queue" do
      expect(result).to be_success
      expect(redis_client).not_to have_received(:zrangebyscore)
      expect(Contracts::FlagRefreshedJob).not_to have_been_enqueued
    end
  end

  context "when the redis store is not configured" do
    let(:redis_url) { nil }

    it "flags no contract" do
      expect(result).to be_success
      expect(Redis).not_to have_received(:new)
      expect(Contracts::FlagRefreshedJob).not_to have_been_enqueued
    end
  end

  context "when the redis store url has a redis:// prefix" do
    let(:redis_url) { "redis://localhost:6379" }

    it "connects to that url" do
      expect(result).to be_success
      expect(Redis).to have_received(:new).with(hash_including(url: redis_url))
    end
  end

  context "when the redis store url has a rediss:// prefix" do
    let(:redis_url) { "rediss://localhost:6379" }

    it "connects to that url over TLS" do
      expect(result).to be_success
      expect(Redis).to have_received(:new).with(hash_including(url: redis_url, ssl: true))
    end
  end

  context "when the redis store url has no prefix" do
    it "connects over redis://" do
      expect(result).to be_success
      expect(Redis).to have_received(:new).with(hash_including(url: "redis://localhost:6379"))
    end
  end
end
