# frozen_string_literal: true

require "rails_helper"

RSpec.describe UsageMonitoring::EvaluateRealtimeUsageAlertsService do
  subject(:result) { described_class.call(subscription:, codes:, watermark_ms:) }

  let_it_be(:organization) { create(:organization) }
  let_it_be(:customer) { create(:customer, organization:) }
  let_it_be(:subscription) { create(:subscription, organization:, customer:) }
  let_it_be(:billable_metric) { create(:billable_metric, organization:, code: "api_calls") }

  let(:codes) { [billable_metric.code] }
  let(:watermark_ms) { 1_795_000_000_000 }
  let(:wait_reason) { nil }

  # Created first but dated after the metric alert, so the evaluation order comes from the query, not the insert.
  let(:plan_alert) do
    create(:usage_current_amount_alert, organization:, subscription_external_id: subscription.external_id, created_at: 1.minute.ago)
  end
  let(:metric_alert) do
    create(
      :billable_metric_current_usage_units_alert,
      organization:, billable_metric:, subscription_external_id: subscription.external_id, created_at: 2.minutes.ago
    )
  end

  let(:evaluation_duration) { Yabeda.usage_monitoring.usage_alerts_evaluation_duration }

  before do
    freeze_time
    plan_alert
    metric_alert

    allow(RealtimeUsage).to receive(:consistent_reads).and_yield
    allow(RealtimeUsage::WaitForBucketsService).to receive(:call)
      .and_return(RealtimeUsage::WaitForBucketsService::Result.new.tap { it.reason = wait_reason })
    allow(UsageMonitoring::EvaluateSubscriptionUsageAlertsService).to receive(:call!)
    allow(evaluation_duration).to receive(:measure)
  end

  it "evaluates the plan total alert and the alerts of the triggered metrics, oldest first" do
    expect(result.reason).to be_nil

    expect(UsageMonitoring::EvaluateSubscriptionUsageAlertsService).to have_received(:call!)
      .with(subscription:, alerts: [metric_alert, plan_alert])
  end

  it "waits for the buckets to reach the watermark, with consistent reads" do
    result

    expect(RealtimeUsage).to have_received(:consistent_reads)
    expect(RealtimeUsage::WaitForBucketsService).to have_received(:call).with(
      organization_id: organization.id,
      pending: {subscription.id => watermark_ms},
      lane: :usage_alerts,
      log_context: {subscription_id: subscription.id}
    )
  end

  it "measures the evaluation" do
    result

    expect(evaluation_duration).to have_received(:measure).with({}, 0.0)
  end

  context "with alerts that the triggered metrics cannot move" do
    let(:other_metric_alert) do
      create(:billable_metric_current_usage_units_alert, organization:, subscription_external_id: subscription.external_id)
    end
    let(:lifetime_alert) do
      create(:billable_metric_lifetime_usage_units_alert, organization:, billable_metric:, subscription_external_id: subscription.external_id)
    end

    before do
      other_metric_alert
      lifetime_alert
    end

    it "leaves them out" do
      result

      expect(UsageMonitoring::EvaluateSubscriptionUsageAlertsService).to have_received(:call!)
        .with(subscription:, alerts: [metric_alert, plan_alert])
    end
  end

  context "with several triggered metrics" do
    let(:other_metric) { create(:billable_metric, organization:, code: "storage") }
    let(:codes) { [billable_metric.code, other_metric.code] }
    let(:other_metric_alert) do
      create(:billable_metric_current_usage_amount_alert, organization:, billable_metric: other_metric, subscription_external_id: subscription.external_id)
    end

    before { other_metric_alert }

    it "evaluates the alerts of every metric at once" do
      result

      expect(UsageMonitoring::EvaluateSubscriptionUsageAlertsService).to have_received(:call!)
        .with(subscription:, alerts: [metric_alert, plan_alert, other_metric_alert]).once
    end
  end

  context "with only per-metric alerts on other metrics" do
    let(:plan_alert) { nil }
    let(:metric_alert) do
      create(:billable_metric_current_usage_units_alert, organization:, subscription_external_id: subscription.external_id)
    end

    it "returns no_alert without waiting" do
      expect(result.reason).to eq(:no_alert)

      expect(RealtimeUsage::WaitForBucketsService).not_to have_received(:call)
      expect(UsageMonitoring::EvaluateSubscriptionUsageAlertsService).not_to have_received(:call!)
    end
  end

  context "with an alert on a deleted metric of the triggered code" do
    let(:plan_alert) { nil }
    let(:codes) { ["deleted_calls"] }
    let(:metric_alert) do
      deleted_metric = create(:billable_metric, organization:, code: "deleted_calls", deleted_at: 1.day.ago)
      create(:billable_metric_current_usage_units_alert, organization:, billable_metric: deleted_metric, subscription_external_id: subscription.external_id)
    end

    it "returns no_alert" do
      expect(result.reason).to eq(:no_alert)
    end
  end

  context "with alerts of another organization on the same subscription external id" do
    let(:plan_alert) { nil }
    let(:metric_alert) do
      other_organization = create(:organization)
      other_metric = create(:billable_metric, organization: other_organization, code: billable_metric.code)
      create(:billable_metric_current_usage_units_alert, organization: other_organization, billable_metric: other_metric, subscription_external_id: subscription.external_id)
    end

    it "returns no_alert" do
      expect(result.reason).to eq(:no_alert)
    end
  end

  context "when the buckets do not reach the watermark in time" do
    let(:wait_reason) { :bucket_wait_timeout }

    it "returns the reason without evaluating" do
      expect(result.reason).to eq(:bucket_wait_timeout)

      expect(UsageMonitoring::EvaluateSubscriptionUsageAlertsService).not_to have_received(:call!)
      expect(evaluation_duration).not_to have_received(:measure)
    end
  end
end
