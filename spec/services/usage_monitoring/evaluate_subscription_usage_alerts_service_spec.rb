# frozen_string_literal: true

require "rails_helper"

RSpec.describe UsageMonitoring::EvaluateSubscriptionUsageAlertsService do
  subject(:result) { described_class.call(subscription:, alerts:, lifetime_usage:, full_plan_usage:) }

  let_it_be(:organization, refind: true) { create(:organization) }
  let_it_be(:customer) { create(:customer, organization:) }
  let_it_be(:billable_metric) { create(:billable_metric, organization:) }

  let(:subscription) { create(:subscription, customer:, organization:) }
  let(:lifetime_usage) { create(:lifetime_usage, subscription:, organization:) }
  let(:full_plan_usage) { nil }
  let(:computed_usage) { instance_double(SubscriptionUsage) }
  let(:usage_result) { Invoices::CustomerUsageService::Result.new.tap { it.usage = computed_usage } }
  let(:charge) { create(:standard_charge, plan: subscription.plan, billable_metric:) }

  let(:amount_alert) { create(:usage_current_amount_alert, organization:, subscription_external_id: subscription.external_id) }
  let(:metric_amount_alert) { create(:billable_metric_current_usage_amount_alert, billable_metric:, organization:, subscription_external_id: subscription.external_id) }
  let(:metric_units_alert) { create(:billable_metric_current_usage_units_alert, billable_metric:, organization:, subscription_external_id: subscription.external_id) }
  let(:lifetime_alert) { create(:lifetime_usage_amount_alert, organization:, subscription_external_id: subscription.external_id) }

  before do
    charge
    allow(::Invoices::CustomerUsageService).to receive(:call).and_return(usage_result)
    allow(UsageMonitoring::ProcessAlertService).to receive(:call)
  end

  context "with a subset of the subscription alerts" do
    let(:alerts) { [metric_units_alert, lifetime_alert] }

    before { amount_alert }

    it "processes only the given alerts" do
      expect(result).to be_success

      expect(UsageMonitoring::ProcessAlertService).to have_received(:call).twice
      expect(UsageMonitoring::ProcessAlertService).to have_received(:call)
        .with(alert: metric_units_alert, alertable: subscription, current_metrics: computed_usage, expected_billable_metric_id: billable_metric.id)
      expect(UsageMonitoring::ProcessAlertService).to have_received(:call)
        .with(alert: lifetime_alert, alertable: subscription, current_metrics: lifetime_usage)
    end
  end

  context "with several current usage alerts" do
    let(:alerts) { [amount_alert, metric_amount_alert, metric_units_alert] }

    it "computes the full plan usage once with the alerting options" do
      result

      expect(::Invoices::CustomerUsageService).to have_received(:call).once.with(
        customer:,
        subscription:,
        apply_taxes: false,
        with_cache: true,
        use_usage_buckets: true
      )
      alerts.each do |alert|
        expect(UsageMonitoring::ProcessAlertService).to have_received(:call)
          .with(alert:, alertable: subscription, current_metrics: computed_usage, expected_billable_metric_id: alert.billable_metric_id)
      end
    end

    context "when a full plan usage is given" do
      let(:full_plan_usage) { instance_double(SubscriptionUsage) }

      it "reuses it without computing a usage" do
        result

        expect(::Invoices::CustomerUsageService).not_to have_received(:call)
        alerts.each do |alert|
          expect(UsageMonitoring::ProcessAlertService).to have_received(:call)
            .with(alert:, alertable: subscription, current_metrics: full_plan_usage, expected_billable_metric_id: alert.billable_metric_id)
        end
      end
    end
  end

  context "with per-metric alerts only" do
    let(:other_metric) { create(:billable_metric, organization:) }
    let(:other_charges) { create_list(:standard_charge, 2, plan: subscription.plan, billable_metric: other_metric) }
    let(:other_metric_alert) { create(:billable_metric_current_usage_units_alert, billable_metric: other_metric, organization:, subscription_external_id: subscription.external_id) }
    let(:alerts) { [metric_amount_alert, metric_units_alert, other_metric_alert] }

    before do
      other_charges
      create(:standard_charge, plan: subscription.plan)
    end

    it "computes one usage scoped to the charges of their metrics, with the alerting options" do
      result

      expect(::Invoices::CustomerUsageService).to have_received(:call).once.with(
        customer:,
        subscription:,
        apply_taxes: false,
        with_cache: true,
        use_usage_buckets: true,
        usage_filters: have_attributes(filter_by_charge_id: match_array([charge.id, *other_charges.map(&:id)]))
      )
      alerts.each do |alert|
        expect(UsageMonitoring::ProcessAlertService).to have_received(:call)
          .with(alert:, alertable: subscription, current_metrics: computed_usage, expected_billable_metric_id: alert.billable_metric_id)
      end
    end

    context "when the subscription plan is overridden" do
      let(:parent_plan) { create(:plan, organization:) }
      let(:subscription) { create(:subscription, customer:, organization:, plan: create(:plan, organization:, parent: parent_plan)) }

      before { create(:standard_charge, plan: parent_plan, billable_metric:) }

      it "scopes the usage to the charges of the subscription plan" do
        result

        expect(::Invoices::CustomerUsageService).to have_received(:call).once.with(
          hash_including(usage_filters: have_attributes(filter_by_charge_id: match_array([charge.id, *other_charges.map(&:id)])))
        )
      end
    end

    context "when a charge is removed from the plan before the usage is computed" do
      let(:usage_result) { Invoices::CustomerUsageService::Result.new.not_found_failure!(resource: "charge") }

      it "evaluates the alerts against an empty usage" do
        expect(result).to be_success

        alerts.each do |alert|
          expect(UsageMonitoring::ProcessAlertService).to have_received(:call)
            .with(alert:, alertable: subscription, current_metrics: have_attributes(fees: []), expected_billable_metric_id: alert.billable_metric_id)
        end
      end
    end
  end

  context "with a per-metric alert on a metric not on the plan" do
    let(:charge) { nil }
    let(:alerts) { [metric_units_alert] }

    it "evaluates the alert against an empty usage without computing one" do
      result

      expect(::Invoices::CustomerUsageService).not_to have_received(:call)
      expect(UsageMonitoring::ProcessAlertService).to have_received(:call)
        .with(alert: metric_units_alert, alertable: subscription, current_metrics: have_attributes(fees: []), expected_billable_metric_id: billable_metric.id)
    end

    context "when the billing period rolled over since the last evaluation" do
      let(:metric_units_alert) do
        create(
          :billable_metric_current_usage_units_alert,
          billable_metric:,
          organization:,
          subscription_external_id: subscription.external_id,
          previous_value: 5,
          last_processed_at: 2.months.ago
        )
      end

      before { allow(UsageMonitoring::ProcessAlertService).to receive(:call).and_call_original }

      it "keeps the previous value, triggers nothing and stamps the evaluation" do
        freeze_time do
          expect { result }.not_to change(UsageMonitoring::TriggeredAlert, :count)

          expect(metric_units_alert.reload).to have_attributes(previous_value: 5, last_processed_at: Time.current)
        end
      end
    end
  end

  context "when the usage cannot be computed" do
    let(:alerts) { [amount_alert, metric_units_alert, lifetime_alert] }

    before do
      allow(::Invoices::CustomerUsageService).to receive(:call).and_raise(StandardError, "usage failed")
    end

    it "computes it once, processes the lifetime alerts only and raises" do
      expect { result }.to raise_error(StandardError, "usage failed")

      expect(::Invoices::CustomerUsageService).to have_received(:call).once
      expect(UsageMonitoring::ProcessAlertService).to have_received(:call).once
      expect(UsageMonitoring::ProcessAlertService).to have_received(:call)
        .with(alert: lifetime_alert, alertable: subscription, current_metrics: lifetime_usage)
    end

    context "when it returns a failure" do
      let(:usage_result) do
        Invoices::CustomerUsageService::Result.new.service_failure!(code: "usage_buckets_read_failure", message: "unreachable")
      end

      before { allow(::Invoices::CustomerUsageService).to receive(:call).and_return(usage_result) }

      it "raises the failure after the lifetime alerts" do
        expect { result }.to raise_error(BaseService::ServiceFailure)

        expect(UsageMonitoring::ProcessAlertService).to have_received(:call).once
        expect(UsageMonitoring::ProcessAlertService).to have_received(:call)
          .with(alert: lifetime_alert, alertable: subscription, current_metrics: lifetime_usage)
      end
    end
  end

  context "with lifetime alerts only" do
    let(:alerts) { [lifetime_alert] }

    it "does not compute the current usage" do
      result

      expect(::Invoices::CustomerUsageService).not_to have_received(:call)
    end
  end

  context "without a lifetime usage given" do
    let(:lifetime_usage) { nil }
    let(:alerts) { [lifetime_alert] }

    it "creates and uses the subscription lifetime usage" do
      expect { result }.to change(LifetimeUsage, :count).by(1)

      expect(UsageMonitoring::ProcessAlertService).to have_received(:call)
        .with(alert: lifetime_alert, alertable: subscription, current_metrics: subscription.reload.lifetime_usage)
    end
  end

  context "with a billable_metric_lifetime_usage_units alert" do
    let(:lifetime_units_alert) do
      create(:billable_metric_lifetime_usage_units_alert, billable_metric:, organization:, subscription_external_id: subscription.external_id)
    end
    let(:alerts) { [lifetime_units_alert] }

    it "enqueues ProcessLifetimeUsageAlertJob after the processing interval" do
      freeze_time do
        result

        expect(UsageMonitoring::ProcessLifetimeUsageAlertJob)
          .to have_been_enqueued.with(alert: lifetime_units_alert, subscription:).at(1.minute.from_now)
      end
      expect(::Invoices::CustomerUsageService).not_to have_received(:call)
    end
  end

  context "when the job enqueue runs inside a transaction" do
    let(:lifetime_units_alert) do
      create(:billable_metric_lifetime_usage_units_alert, billable_metric:, organization:, subscription_external_id: subscription.external_id)
    end
    let(:alerts) { [lifetime_units_alert] }

    it "enqueues ProcessLifetimeUsageAlertJob after the commit" do
      expect { result }.to have_enqueued_job_after_commit(UsageMonitoring::ProcessLifetimeUsageAlertJob)
        .with(alert: lifetime_units_alert, subscription:)
    end
  end

  context "with an alert of another subscription" do
    let(:other_alert) { create(:usage_current_amount_alert, organization:, subscription_external_id: create(:subscription, customer:, organization:).external_id) }
    let(:alerts) { [lifetime_alert, other_alert] }

    it "raises without processing any alert" do
      expect { result }.to raise_error(ArgumentError, /#{other_alert.id}/)

      expect(UsageMonitoring::ProcessAlertService).not_to have_received(:call)
    end
  end

  context "with an alert of another organization" do
    let(:other_organization) { create(:organization) }
    let(:other_alert) { create(:usage_current_amount_alert, organization: other_organization, subscription_external_id: subscription.external_id) }
    let(:alerts) { [lifetime_alert, other_alert] }

    it "raises without processing any alert" do
      expect { result }.to raise_error(ArgumentError, /#{other_alert.id}/)

      expect(UsageMonitoring::ProcessAlertService).not_to have_received(:call)
    end
  end

  context "when one alert fails" do
    let(:alerts) { [amount_alert, metric_units_alert, lifetime_alert] }

    before do
      allow(UsageMonitoring::ProcessAlertService).to receive(:call)
        .with(alert: amount_alert, alertable: subscription, current_metrics: computed_usage, expected_billable_metric_id: nil)
        .and_raise(StandardError, "first alert failed")
      allow(UsageMonitoring::ProcessAlertService).to receive(:call)
        .with(alert: metric_units_alert, alertable: subscription, current_metrics: computed_usage, expected_billable_metric_id: billable_metric.id)
        .and_raise(StandardError, "second alert failed")
    end

    it "processes the other alerts and raises the first error" do
      expect { result }.to raise_error(StandardError, "first alert failed")

      expect(UsageMonitoring::ProcessAlertService).to have_received(:call)
        .with(alert: lifetime_alert, alertable: subscription, current_metrics: lifetime_usage)
    end
  end

  context "with no alerts" do
    let(:alerts) { [] }

    it "does nothing" do
      expect(result).to be_success

      expect(::Invoices::CustomerUsageService).not_to have_received(:call)
      expect(UsageMonitoring::ProcessAlertService).not_to have_received(:call)
    end
  end

  describe "the scoped usage and the full plan usage agree" do
    let(:other_metric) { create(:billable_metric, organization:) }
    let(:metric_off_plan) { create(:billable_metric, organization:) }
    let(:off_plan_alert) do
      create(:billable_metric_current_usage_units_alert, billable_metric: metric_off_plan, organization:, subscription_external_id: subscription.external_id, previous_value: 7)
    end
    let(:alerts) { [metric_units_alert, off_plan_alert] }

    let(:full_plan_value) do
      usage = Invoices::CustomerUsageService.call!(customer:, subscription:, apply_taxes: false, with_cache: false, use_usage_buckets: true).usage
      metric_units_alert.find_value(usage)
    end

    before do
      allow(::Invoices::CustomerUsageService).to receive(:call).and_call_original
      allow(UsageMonitoring::ProcessAlertService).to receive(:call).and_call_original
      create(:standard_charge, plan: subscription.plan, billable_metric: other_metric)
    end

    context "with the usage read from the events" do
      before do
        create_list(:event, 3, organization_id: organization.id, subscription:, code: billable_metric.code)
        create_list(:event, 2, organization_id: organization.id, subscription:, code: other_metric.code)
      end

      it "gives the alert the value of the full plan usage" do
        result

        expect(full_plan_value).to eq(3)
        expect(metric_units_alert.reload.previous_value).to eq(full_plan_value)
        expect(off_plan_alert.reload.previous_value).to eq(7)
      end
    end

    context "with the usage served from the buckets", clickhouse: {clean_before: true} do
      include_context "with realtime usage availability"

      before do
        organization.update!(clickhouse_events_store: true)
        organization.enable_feature_flag!(:realtime_usage)
        create(:tax, :applied_to_billing_entity, organization:, rate: 0)

        [[billable_metric, charge, 4], [other_metric, subscription.plan.charges.find_by(billable_metric: other_metric), 2]].each do |metric, metric_charge, count|
          create_list(:clickhouse_events_enriched, count, organization_id: organization.id, external_subscription_id: subscription.external_id, code: metric.code, timestamp: Time.current)
          create(
            :clickhouse_usage_bucket,
            organization:, customer:, subscription:, charge: metric_charge, billable_metric: metric,
            bucket: Time.current.beginning_of_hour,
            units: count.to_s,
            events_count: count,
            aggregation_type: "count"
          )
        end
      end

      it "gives the alert the value of the full plan usage" do
        result

        expect(full_plan_value).to eq(4)
        expect(metric_units_alert.reload.previous_value).to eq(full_plan_value)
        expect(off_plan_alert.reload.previous_value).to eq(7)
      end
    end
  end
end
