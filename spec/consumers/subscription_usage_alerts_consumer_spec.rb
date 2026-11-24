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
  let(:billable_metric) { create(:billable_metric, organization:, code: "api_calls") }
  let(:watermark_ms) { (Time.current.to_f * 1000).to_i }
  let(:alerts_enabled) { "true" }
  let(:wait_reason) { nil }

  let(:trigger) do
    {
      organization_id: organization.id,
      customer_id: customer.id,
      subscription_id: subscription.id,
      code: billable_metric.code,
      last_ingested_at: watermark_ms,
      target_wallet_code: ""
    }
  end

  let(:plan_alert) do
    create(:usage_current_amount_alert, organization:, subscription_external_id: subscription.external_id)
  end
  let(:metric_alert) do
    create(:billable_metric_current_usage_units_alert, organization:, billable_metric:, subscription_external_id: subscription.external_id)
  end

  let(:outcomes) { Yabeda.usage_monitoring.usage_alerts_outcomes_total }
  let(:latency) { Yabeda.usage_monitoring.usage_alerts_latency }
  let(:evaluation_duration) { Yabeda.usage_monitoring.usage_alerts_evaluation_duration }

  before do
    ENV["LAGO_REALTIME_USAGE_ALERTS_ENABLED"] = alerts_enabled
    plan_alert
    metric_alert

    allow(RealtimeUsage::BucketWatermark).to receive(:consistent_reads).and_yield
    allow(RealtimeUsage::BucketWatermark).to receive(:wait).and_return(wait_reason)
    allow(UsageMonitoring::EvaluateSubscriptionUsageAlertsService).to receive(:call!)
    allow(outcomes).to receive(:increment)
    allow(latency).to receive(:measure)
    allow(evaluation_duration).to receive(:measure)

    karafka.produce(trigger.to_json)
  end

  after { ENV["LAGO_REALTIME_USAGE_ALERTS_ENABLED"] = nil }

  it "evaluates the plan total alert and the alerts of the trigger's metric" do
    other_metric_alert = create(:billable_metric_current_usage_units_alert, organization:, subscription_external_id: subscription.external_id)
    lifetime_alert = create(:billable_metric_lifetime_usage_units_alert, organization:, billable_metric:, subscription_external_id: subscription.external_id)

    consumer.consume

    expect(UsageMonitoring::EvaluateSubscriptionUsageAlertsService).to have_received(:call!)
      .with(subscription:, alerts: contain_exactly(plan_alert, metric_alert))
    expect([plan_alert, metric_alert]).not_to include(other_metric_alert, lifetime_alert)
  end

  it "waits for the buckets to reach the trigger watermark, with consistent reads" do
    consumer.consume

    expect(RealtimeUsage::BucketWatermark).to have_received(:consistent_reads)
    expect(RealtimeUsage::BucketWatermark).to have_received(:wait).with(
      organization_id: organization.id,
      pending: {subscription.id => watermark_ms},
      lane: :usage_alerts
    )
  end

  it "counts the evaluation and measures it" do
    consumer.consume

    expect(outcomes).to have_received(:increment).with({outcome: "evaluated", reason: "none"}, by: 1)
    expect(latency).to have_received(:measure).with({}, be_within(60).of(0))
    expect(evaluation_duration).to have_received(:measure).with({}, be_within(60).of(0))
  end

  context "with several triggers for the same subscription" do
    let(:other_metric) { create(:billable_metric, organization:, code: "storage") }
    let(:other_metric_alert) do
      create(:billable_metric_current_usage_amount_alert, organization:, billable_metric: other_metric, subscription_external_id: subscription.external_id)
    end

    before do
      other_metric_alert
      karafka.produce(trigger.merge(code: other_metric.code, last_ingested_at: watermark_ms + 1000).to_json)
    end

    it "evaluates once, at the latest watermark, the alerts of every metric of the batch" do
      consumer.consume

      expect(RealtimeUsage::BucketWatermark).to have_received(:wait).with(
        organization_id: organization.id,
        pending: {subscription.id => watermark_ms + 1000},
        lane: :usage_alerts
      ).once
      expect(UsageMonitoring::EvaluateSubscriptionUsageAlertsService).to have_received(:call!)
        .with(subscription:, alerts: contain_exactly(plan_alert, metric_alert, other_metric_alert)).once
    end
  end

  context "with only per-metric alerts on other metrics" do
    let(:plan_alert) { nil }
    let(:metric_alert) do
      create(:billable_metric_current_usage_units_alert, organization:, subscription_external_id: subscription.external_id)
    end

    it "does not wait or evaluate" do
      consumer.consume

      expect(RealtimeUsage::BucketWatermark).not_to have_received(:wait)
      expect(UsageMonitoring::EvaluateSubscriptionUsageAlertsService).not_to have_received(:call!)
      expect(outcomes).to have_received(:increment).with({outcome: "skipped", reason: "no_alert"}, by: 1)
    end
  end

  context "with an alert on a deleted metric of the trigger's code" do
    let(:plan_alert) { nil }
    let(:billable_metric) { create(:billable_metric, organization:, code: "api_calls", deleted_at: 1.day.ago) }

    it "does not evaluate it" do
      consumer.consume

      expect(UsageMonitoring::EvaluateSubscriptionUsageAlertsService).not_to have_received(:call!)
      expect(outcomes).to have_received(:increment).with({outcome: "skipped", reason: "no_alert"}, by: 1)
    end
  end

  context "with alerts of another organization on the same subscription external id" do
    let(:plan_alert) { nil }
    let(:metric_alert) do
      other_organization = create(:organization)
      other_metric = create(:billable_metric, organization: other_organization, code: billable_metric.code)
      create(:billable_metric_current_usage_units_alert, organization: other_organization, billable_metric: other_metric, subscription_external_id: subscription.external_id)
    end

    it "does not evaluate them" do
      consumer.consume

      expect(UsageMonitoring::EvaluateSubscriptionUsageAlertsService).not_to have_received(:call!)
    end
  end

  context "with a tombstone in the batch" do
    before { karafka.produce(nil) }

    it "evaluates the trigger only" do
      consumer.consume

      expect(UsageMonitoring::EvaluateSubscriptionUsageAlertsService).to have_received(:call!).once
    end
  end

  context "when the alerts lane is off" do
    let(:alerts_enabled) { nil }

    it "leaves the subscription to the sweep" do
      consumer.consume

      expect(UsageMonitoring::EvaluateSubscriptionUsageAlertsService).not_to have_received(:call!)
      expect(outcomes).to have_received(:increment).with({outcome: "skipped", reason: "not_enabled"}, by: 1)
    end
  end

  context "without the realtime_usage_alerts flag" do
    let(:organization) { create(:organization, clickhouse_events_store: true, feature_flags: ["realtime_usage"]) }

    it "leaves the subscription to the sweep" do
      consumer.consume

      expect(UsageMonitoring::EvaluateSubscriptionUsageAlertsService).not_to have_received(:call!)
      expect(outcomes).to have_received(:increment).with({outcome: "skipped", reason: "not_enabled"}, by: 1)
    end
  end

  context "when realtime usage is off for the organization" do
    let(:realtime_usage_enabled) { "false" }

    it "leaves the subscription to the sweep" do
      consumer.consume

      expect(UsageMonitoring::EvaluateSubscriptionUsageAlertsService).not_to have_received(:call!)
      expect(outcomes).to have_received(:increment).with({outcome: "skipped", reason: "not_enabled"}, by: 1)
    end
  end

  context "when the subscription is terminated" do
    let(:subscription) { create(:subscription, :terminated, organization:, customer:) }

    it "does not evaluate" do
      consumer.consume

      expect(UsageMonitoring::EvaluateSubscriptionUsageAlertsService).not_to have_received(:call!)
      expect(outcomes).to have_received(:increment).with({outcome: "skipped", reason: "subscription_not_found"}, by: 1)
    end
  end

  context "when the subscription belongs to another organization" do
    let(:trigger) { super().merge(subscription_id: create(:subscription).id) }

    it "does not evaluate" do
      consumer.consume

      expect(UsageMonitoring::EvaluateSubscriptionUsageAlertsService).not_to have_received(:call!)
      expect(outcomes).to have_received(:increment).with({outcome: "skipped", reason: "subscription_not_found"}, by: 1)
    end
  end

  context "without a subscription id on the payload" do
    let(:trigger) { super().except(:subscription_id) }

    it "does not evaluate" do
      consumer.consume

      expect(UsageMonitoring::EvaluateSubscriptionUsageAlertsService).not_to have_received(:call!)
      expect(outcomes).to have_received(:increment).with({outcome: "skipped", reason: "subscription_not_found"}, by: 1)
    end
  end

  context "without a watermark on the payload" do
    let(:trigger) { super().except(:last_ingested_at) }

    it "does not evaluate on buckets it cannot wait for" do
      consumer.consume

      expect(UsageMonitoring::EvaluateSubscriptionUsageAlertsService).not_to have_received(:call!)
      expect(outcomes).to have_received(:increment).with({outcome: "skipped", reason: "no_watermark"}, by: 1)
    end
  end

  context "when the buckets do not reach the watermark in time" do
    let(:wait_reason) { :bucket_wait_timeout }

    it "leaves the subscription to the sweep" do
      consumer.consume

      expect(UsageMonitoring::EvaluateSubscriptionUsageAlertsService).not_to have_received(:call!)
      expect(outcomes).to have_received(:increment).with({outcome: "skipped", reason: "bucket_wait_timeout"}, by: 1)
      expect(latency).not_to have_received(:measure)
    end
  end

  context "when the watermark is stale" do
    let(:wait_reason) { :stale_watermark }

    it "leaves the subscription to the sweep" do
      consumer.consume

      expect(UsageMonitoring::EvaluateSubscriptionUsageAlertsService).not_to have_received(:call!)
      expect(outcomes).to have_received(:increment).with({outcome: "skipped", reason: "stale_watermark"}, by: 1)
    end
  end

  context "when the batch hits its deadline" do
    before do
      stub_const("#{described_class}::CONSUME_DEADLINE", -1.second)
      allow(Rails.logger).to receive(:warn)
    end

    it "leaves every remaining subscription to the sweep" do
      consumer.consume

      expect(UsageMonitoring::EvaluateSubscriptionUsageAlertsService).not_to have_received(:call!)
      expect(outcomes).to have_received(:increment).with({outcome: "skipped", reason: "deadline"}, by: 1)
      expect(Rails.logger).to have_received(:warn).with(/hit its deadline/)
    end
  end

  context "when an evaluation raises" do
    let(:other_subscription) { create(:subscription, organization:, customer:) }
    let(:other_alert) do
      create(:usage_current_amount_alert, organization:, subscription_external_id: other_subscription.external_id)
    end

    before do
      other_alert
      karafka.produce(trigger.merge(subscription_id: other_subscription.id).to_json)

      allow(UsageMonitoring::EvaluateSubscriptionUsageAlertsService).to receive(:call!)
        .with(hash_including(subscription:))
        .and_raise(ActiveRecord::StaleObjectError.new(nil, "update"))
      allow(Rails.logger).to receive(:error)
      allow(Sentry).to receive(:capture_exception)
    end

    it "keeps consuming the batch" do
      expect { consumer.consume }.not_to raise_error

      expect(UsageMonitoring::EvaluateSubscriptionUsageAlertsService).to have_received(:call!)
        .with(subscription: other_subscription, alerts: [other_alert])
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
