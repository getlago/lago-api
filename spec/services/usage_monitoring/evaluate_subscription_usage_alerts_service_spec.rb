# frozen_string_literal: true

require "rails_helper"

RSpec.describe UsageMonitoring::EvaluateSubscriptionUsageAlertsService do
  subject(:result) { described_class.call(subscription:, alerts:, lifetime_usage:, full_plan_usage:) }

  let_it_be(:organization) { create(:organization) }
  let_it_be(:customer) { create(:customer, organization:) }
  let_it_be(:billable_metric) { create(:billable_metric, organization:) }

  let(:subscription) { create(:subscription, customer:, organization:) }
  let(:lifetime_usage) { create(:lifetime_usage, subscription:, organization:) }
  let(:full_plan_usage) { nil }
  let(:computed_usage) { instance_double(SubscriptionUsage) }

  let(:amount_alert) { create(:usage_current_amount_alert, organization:, subscription_external_id: subscription.external_id) }
  let(:metric_amount_alert) { create(:billable_metric_current_usage_amount_alert, billable_metric:, organization:, subscription_external_id: subscription.external_id) }
  let(:metric_units_alert) { create(:billable_metric_current_usage_units_alert, billable_metric:, organization:, subscription_external_id: subscription.external_id) }
  let(:lifetime_alert) { create(:lifetime_usage_amount_alert, organization:, subscription_external_id: subscription.external_id) }

  before do
    allow(::Invoices::CustomerUsageService).to receive(:call)
      .and_return(instance_double(Invoices::CustomerUsageService::Result, usage: computed_usage))
    allow(UsageMonitoring::ProcessAlertService).to receive(:call)
  end

  context "with a subset of the subscription alerts" do
    let(:alerts) { [metric_units_alert, lifetime_alert] }

    before { amount_alert }

    it "processes only the given alerts" do
      expect(result).to be_success

      expect(UsageMonitoring::ProcessAlertService).to have_received(:call).twice
      expect(UsageMonitoring::ProcessAlertService).to have_received(:call)
        .with(alert: metric_units_alert, alertable: subscription, current_metrics: computed_usage)
      expect(UsageMonitoring::ProcessAlertService).to have_received(:call)
        .with(alert: lifetime_alert, alertable: subscription, current_metrics: lifetime_usage)
    end
  end

  context "with several current usage alerts" do
    let(:alerts) { [amount_alert, metric_amount_alert, metric_units_alert] }

    it "computes the current usage once with the alerting options" do
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
          .with(alert:, alertable: subscription, current_metrics: computed_usage)
      end
    end

    context "when a full plan usage is given" do
      let(:full_plan_usage) { instance_double(SubscriptionUsage) }

      it "reuses it without computing a usage" do
        result

        expect(::Invoices::CustomerUsageService).not_to have_received(:call)
        alerts.each do |alert|
          expect(UsageMonitoring::ProcessAlertService).to have_received(:call)
            .with(alert:, alertable: subscription, current_metrics: full_plan_usage)
        end
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
        .with(alert: amount_alert, alertable: subscription, current_metrics: computed_usage)
        .and_raise(StandardError, "first alert failed")
      allow(UsageMonitoring::ProcessAlertService).to receive(:call)
        .with(alert: metric_units_alert, alertable: subscription, current_metrics: computed_usage)
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
end
