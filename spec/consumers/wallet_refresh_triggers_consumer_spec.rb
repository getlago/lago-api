# frozen_string_literal: true

require "rails_helper"

RSpec.describe WalletRefreshTriggersConsumer do
  subject(:consumer) { karafka.consumer_for(ENV["LAGO_KAFKA_REALTIME_USAGE_TRIGGERS_TOPIC"]) }

  include_context "with realtime usage availability"

  let(:organization) do
    create(:organization, clickhouse_events_store: true, feature_flags: ["realtime_usage"])
  end
  let(:customer) { create(:customer, organization:) }
  let(:plan) { create(:plan, organization:) }
  let(:subscription) { create(:subscription, organization:, customer:, plan:) }
  let(:watermark_ms) { (Time.current.to_f * 1000).to_i }

  let(:refresh_result) do
    Wallets::RealtimeRefreshService::Result.new.tap { |r| r.wallets = [] }
  end

  let(:trigger) do
    {
      organization_id: organization.id,
      customer_id: customer.id,
      subscription_id: subscription.id,
      last_ingested_at: watermark_ms,
      target_wallet_code: nil
    }
  end

  let(:wallet_status) { :active }

  let(:outcomes) { Yabeda.realtime_usage.wallet_refresh_outcomes_total }
  let(:consumed_messages) { Yabeda.realtime_usage.wallet_refresh_messages_total }
  let(:latency) { Yabeda.realtime_usage.wallet_refresh_latency }

  before do
    create(:wallet, customer:, organization:, status: wallet_status)
    allow(Wallets::RealtimeRefreshService).to receive(:call).and_return(refresh_result)
    allow(outcomes).to receive(:increment)
    allow(consumed_messages).to receive(:increment)
    allow(latency).to receive(:measure)
    karafka.produce(trigger.to_json)
  end

  it "refreshes the customer wallets" do
    consumer.consume

    expect(Wallets::RealtimeRefreshService).to have_received(:call).with(
      organization_id: organization.id,
      customer_id: customer.id,
      wallet_codes: [],
      expected_ingested_at: {subscription.id => watermark_ms}
    )
  end

  it "counts the refresh" do
    consumer.consume

    expect(outcomes).to have_received(:increment).with({outcome: "refreshed", reason: "none"}, by: 1)
  end

  it "counts the messages it consumed" do
    consumer.consume

    expect(consumed_messages).to have_received(:increment).with({kind: "trigger"}, by: 1)
  end

  it "measures the latency from the trigger watermark" do
    consumer.consume

    expect(latency).to have_received(:measure).with({}, be_within(60).of(0))
  end

  context "with several triggers for the same customer" do
    before do
      karafka.produce(trigger.merge(last_ingested_at: watermark_ms + 1000, target_wallet_code: "gold").to_json)
    end

    it "refreshes once, at the latest watermark" do
      consumer.consume

      expect(Wallets::RealtimeRefreshService).to have_received(:call).with(
        organization_id: organization.id,
        customer_id: customer.id,
        wallet_codes: ["gold"],
        expected_ingested_at: {subscription.id => watermark_ms + 1000}
      ).once
    end

    it "counts both messages against the one refresh they collapsed into" do
      consumer.consume

      expect(consumed_messages).to have_received(:increment).with({kind: "trigger"}, by: 2)
      expect(outcomes).to have_received(:increment).with({outcome: "refreshed", reason: "none"}, by: 1)
    end
  end

  context "without a subscription id on the payload" do
    let(:trigger) do
      {
        organization_id: organization.id,
        customer_id: customer.id,
        last_ingested_at: watermark_ms,
        target_wallet_code: nil
      }
    end

    it "refreshes without a watermark to wait on" do
      consumer.consume

      expect(Wallets::RealtimeRefreshService).to have_received(:call).with(
        organization_id: organization.id,
        customer_id: customer.id,
        wallet_codes: [],
        expected_ingested_at: {}
      )
    end
  end

  context "when realtime usage is off for the organization" do
    let(:realtime_usage_enabled) { "false" }

    it "does not refresh" do
      consumer.consume

      expect(Wallets::RealtimeRefreshService).not_to have_received(:call)
    end

    it "counts the skip" do
      consumer.consume

      expect(outcomes).to have_received(:increment)
        .with({outcome: "skipped", reason: "organization_not_served"}, by: 1)
    end
  end

  context "when the organization does not read the clickhouse events store" do
    let(:organization) { create(:organization, feature_flags: ["realtime_usage"]) }

    it "does not refresh" do
      consumer.consume

      expect(Wallets::RealtimeRefreshService).not_to have_received(:call)
    end
  end

  context "when the organization deduplicates its events" do
    let(:organization) do
      create(
        :organization,
        clickhouse_events_store: true,
        clickhouse_deduplication_enabled: true,
        feature_flags: ["realtime_usage"]
      )
    end

    it "does not refresh" do
      consumer.consume

      expect(Wallets::RealtimeRefreshService).not_to have_received(:call)
    end
  end

  context "without an active wallet" do
    let(:wallet_status) { :terminated }

    it "does not refresh" do
      consumer.consume

      expect(Wallets::RealtimeRefreshService).not_to have_received(:call)
    end

    it "counts the skip" do
      consumer.consume

      expect(outcomes).to have_received(:increment)
        .with({outcome: "skipped", reason: "no_active_wallet"}, by: 1)
    end
  end

  context "when a refresh raises" do
    let(:other_customer) { create(:customer, organization:) }

    before do
      create(:wallet, customer: other_customer, organization:)
      karafka.produce(trigger.merge(customer_id: other_customer.id).to_json)

      allow(Wallets::RealtimeRefreshService).to receive(:call)
        .with(hash_including(customer_id: customer.id))
        .and_raise(ActiveRecord::StaleObjectError.new(nil, "update"))
      allow(Rails.logger).to receive(:error)
      allow(Sentry).to receive(:capture_exception)
    end

    it "keeps consuming the batch" do
      expect { consumer.consume }.not_to raise_error

      expect(Wallets::RealtimeRefreshService).to have_received(:call)
        .with(hash_including(customer_id: other_customer.id))
    end

    it "reports the error" do
      consumer.consume

      expect(Sentry).to have_received(:capture_exception)
        .with(ActiveRecord::StaleObjectError, extra: {customer_id: customer.id})
    end

    it "counts the failure" do
      consumer.consume

      expect(outcomes).to have_received(:increment).with({outcome: "failed", reason: "refresh_raised"}, by: 1)
    end
  end

  context "when the batch hits its deadline" do
    before do
      stub_const("#{described_class}::CONSUME_DEADLINE", -1.second)
      allow(Rails.logger).to receive(:warn)
    end

    it "leaves the remaining customers to the sweep" do
      consumer.consume

      expect(Wallets::RealtimeRefreshService).not_to have_received(:call)
      expect(Rails.logger).to have_received(:warn).with(/hit its deadline/)
    end

    it "counts every customer behind the cut" do
      consumer.consume

      expect(outcomes).to have_received(:increment).with({outcome: "skipped", reason: "deadline"}, by: 1)
    end
  end

  context "when the refresh service walks away from the customer" do
    let(:refresh_result) do
      Wallets::RealtimeRefreshService::Result.new.tap { |r| r.reason = :stale_watermark }
    end

    it "counts the reason the service reports" do
      consumer.consume

      expect(outcomes).to have_received(:increment).with({outcome: "skipped", reason: "stale_watermark"}, by: 1)
    end

    it "measures no latency for a refresh that did not happen" do
      consumer.consume

      expect(latency).not_to have_received(:measure)
    end
  end

  context "when the refresh service fails" do
    let(:refresh_result) do
      Wallets::RealtimeRefreshService::Result.new.tap { |r| r.service_failure!(code: "boom", message: "boom") }
    end

    before do
      allow(Rails.logger).to receive(:error)
      allow(Sentry).to receive(:capture_message)
    end

    it "counts the failure" do
      consumer.consume

      expect(outcomes).to have_received(:increment).with({outcome: "failed", reason: "refresh_failed"}, by: 1)
    end
  end
end
