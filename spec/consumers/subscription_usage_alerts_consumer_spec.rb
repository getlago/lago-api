# frozen_string_literal: true

require "rails_helper"

RSpec.describe SubscriptionUsageAlertsConsumer do
  subject(:consumer) { karafka.consumer_for(ENV["LAGO_KAFKA_REALTIME_USAGE_TRIGGERS_TOPIC"], :lago_usage_alerts_consumer) }

  include_context "with realtime usage availability"

  let(:organization) do
    create(:organization, clickhouse_events_store: true, feature_flags: %w[realtime_usage realtime_usage_alerts])
  end
  let(:customer) { create(:customer, organization:) }
  let(:subscription) { create(:subscription, organization:, customer:) }
  let(:watermark_ms) { 1_795_000_000_000 }
  let(:alerts_enabled) { "true" }
  let(:evaluation_reason) { nil }

  let(:trigger) do
    {
      organization_id: organization.id,
      customer_id: customer.id,
      subscription_id: subscription.id,
      code: "api_calls",
      last_ingested_at: watermark_ms,
      target_wallet_code: ""
    }
  end

  let(:outcomes) { Yabeda.usage_monitoring.usage_alerts_outcomes_total }
  let(:latency) { Yabeda.usage_monitoring.usage_alerts_latency }

  before do
    ENV["LAGO_REALTIME_USAGE_ALERTS_ENABLED"] = alerts_enabled

    allow(UsageMonitoring::EvaluateRealtimeUsageAlertsService).to receive(:call!)
      .and_return(UsageMonitoring::EvaluateRealtimeUsageAlertsService::Result.new.tap { it.reason = evaluation_reason })
    allow(outcomes).to receive(:increment)
    allow(latency).to receive(:measure)

    karafka.produce(trigger.to_json)
  end

  after { ENV["LAGO_REALTIME_USAGE_ALERTS_ENABLED"] = nil }

  it "evaluates the subscription's alerts for the triggered metric at the trigger watermark" do
    consumer.consume

    expect(UsageMonitoring::EvaluateRealtimeUsageAlertsService).to have_received(:call!)
      .with(subscription:, codes: ["api_calls"], watermark_ms:)
  end

  context "when the evaluation ends 3 seconds after the trigger watermark" do
    around { |example| travel_to(Time.zone.at(1_795_000_003)) { example.run } }

    it "counts the evaluation and measures its latency" do
      consumer.consume

      expect(outcomes).to have_received(:increment).with({outcome: "evaluated", reason: "none"}, by: 1)
      expect(latency).to have_received(:measure).with({}, 3.0)
    end
  end

  context "with several triggers for the same subscription" do
    before do
      karafka.produce(trigger.merge(code: "storage", last_ingested_at: watermark_ms + 1000).to_json)
      karafka.produce(trigger.merge(last_ingested_at: watermark_ms + 500).to_json)
    end

    it "evaluates once, at the latest watermark, for every metric of the batch" do
      consumer.consume

      expect(UsageMonitoring::EvaluateRealtimeUsageAlertsService).to have_received(:call!)
        .with(subscription:, codes: %w[api_calls storage], watermark_ms: watermark_ms + 1000).once
    end
  end

  context "with a tombstone in the batch" do
    before { karafka.produce(nil) }

    it "evaluates the trigger only" do
      consumer.consume

      expect(UsageMonitoring::EvaluateRealtimeUsageAlertsService).to have_received(:call!).once
    end
  end

  context "when the evaluation leaves the subscription to the sweep" do
    let(:evaluation_reason) { :bucket_wait_timeout }

    it "counts the reason and measures no latency" do
      consumer.consume

      expect(outcomes).to have_received(:increment).with({outcome: "skipped", reason: "bucket_wait_timeout"}, by: 1)
      expect(latency).not_to have_received(:measure)
    end
  end

  context "when the alerts lane is off" do
    let(:alerts_enabled) { nil }

    it "leaves the subscription to the sweep" do
      consumer.consume

      expect(UsageMonitoring::EvaluateRealtimeUsageAlertsService).not_to have_received(:call!)
      expect(outcomes).to have_received(:increment).with({outcome: "skipped", reason: "not_enabled"}, by: 1)
    end
  end

  context "without the realtime_usage_alerts flag" do
    let(:organization) { create(:organization, clickhouse_events_store: true, feature_flags: ["realtime_usage"]) }

    it "leaves the subscription to the sweep" do
      consumer.consume

      expect(UsageMonitoring::EvaluateRealtimeUsageAlertsService).not_to have_received(:call!)
      expect(outcomes).to have_received(:increment).with({outcome: "skipped", reason: "not_enabled"}, by: 1)
    end
  end

  context "when realtime usage is off for the organization" do
    let(:realtime_usage_enabled) { "false" }

    it "leaves the subscription to the sweep" do
      consumer.consume

      expect(UsageMonitoring::EvaluateRealtimeUsageAlertsService).not_to have_received(:call!)
      expect(outcomes).to have_received(:increment).with({outcome: "skipped", reason: "not_enabled"}, by: 1)
    end
  end

  context "when the subscription is terminated" do
    let(:subscription) { create(:subscription, :terminated, organization:, customer:) }

    it "does not evaluate" do
      consumer.consume

      expect(UsageMonitoring::EvaluateRealtimeUsageAlertsService).not_to have_received(:call!)
      expect(outcomes).to have_received(:increment).with({outcome: "skipped", reason: "subscription_not_found"}, by: 1)
    end
  end

  context "when the subscription belongs to another organization" do
    let(:trigger) { super().merge(subscription_id: create(:subscription).id) }

    it "does not evaluate" do
      consumer.consume

      expect(UsageMonitoring::EvaluateRealtimeUsageAlertsService).not_to have_received(:call!)
      expect(outcomes).to have_received(:increment).with({outcome: "skipped", reason: "subscription_not_found"}, by: 1)
    end
  end

  context "without a subscription id on the payload" do
    let(:trigger) { super().except(:subscription_id) }

    it "does not evaluate" do
      consumer.consume

      expect(UsageMonitoring::EvaluateRealtimeUsageAlertsService).not_to have_received(:call!)
      expect(outcomes).to have_received(:increment).with({outcome: "skipped", reason: "subscription_not_found"}, by: 1)
    end
  end

  context "without a watermark on the payload" do
    let(:trigger) { super().except(:last_ingested_at) }

    it "does not evaluate on buckets it cannot wait for" do
      consumer.consume

      expect(UsageMonitoring::EvaluateRealtimeUsageAlertsService).not_to have_received(:call!)
      expect(outcomes).to have_received(:increment).with({outcome: "skipped", reason: "no_watermark"}, by: 1)
    end
  end

  context "when the batch hits its deadline" do
    before do
      stub_const("#{described_class}::CONSUME_DEADLINE", -1.second)
      allow(Rails.logger).to receive(:warn)
    end

    it "leaves every remaining subscription to the sweep" do
      consumer.consume

      expect(UsageMonitoring::EvaluateRealtimeUsageAlertsService).not_to have_received(:call!)
      expect(outcomes).to have_received(:increment).with({outcome: "skipped", reason: "deadline"}, by: 1)
      expect(Rails.logger).to have_received(:warn).with(/hit its deadline/)
    end

    context "with a subscription of an organization the lane is off for" do
      let(:other_organization) { create(:organization, clickhouse_events_store: true, feature_flags: ["realtime_usage"]) }
      let(:other_subscription) { create(:subscription, organization: other_organization) }

      before do
        karafka.produce(trigger.merge(organization_id: other_organization.id, subscription_id: other_subscription.id).to_json)
      end

      it "counts it as not enabled rather than cut by the deadline" do
        consumer.consume

        expect(outcomes).to have_received(:increment).with({outcome: "skipped", reason: "not_enabled"}, by: 1)
        expect(outcomes).to have_received(:increment).with({outcome: "skipped", reason: "deadline"}, by: 1)
      end
    end
  end

  context "when an evaluation raises" do
    let(:other_subscription) { create(:subscription, organization:, customer:) }

    before do
      karafka.produce(trigger.merge(subscription_id: other_subscription.id).to_json)

      allow(UsageMonitoring::EvaluateRealtimeUsageAlertsService).to receive(:call!)
        .with(hash_including(subscription:))
        .and_raise(ActiveRecord::StaleObjectError.new(nil, "update"))
      allow(Rails.logger).to receive(:error)
      allow(Sentry).to receive(:capture_exception)
    end

    it "keeps consuming the batch" do
      expect { consumer.consume }.not_to raise_error

      expect(UsageMonitoring::EvaluateRealtimeUsageAlertsService).to have_received(:call!)
        .with(subscription: other_subscription, codes: ["api_calls"], watermark_ms:)
    end

    it "reports and counts the failure" do
      consumer.consume

      expect(Sentry).to have_received(:capture_exception)
        .with(ActiveRecord::StaleObjectError, extra: {subscription_id: subscription.id})
      expect(outcomes).to have_received(:increment).with({outcome: "failed", reason: "evaluation_raised"}, by: 1)
      expect(outcomes).to have_received(:increment).with({outcome: "evaluated", reason: "none"}, by: 1)
    end
  end
end
