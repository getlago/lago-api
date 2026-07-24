# frozen_string_literal: true

require "rails_helper"

RSpec.describe UsageMonitoring::ProcessLifetimeUsageAlertJob do
  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:) }
  let(:subscription) { create(:subscription, customer:, organization:) }
  let(:alert) { create(:billable_metric_lifetime_usage_units_alert, organization:, subscription_external_id: subscription.external_id) }

  it_behaves_like "a unique job" do
    let(:job_args) { [{alert:, subscription:}] }
  end

  it_behaves_like "a configurable queue", "alerts", "SIDEKIQ_ALERTS" do
    let(:arguments) { {alert:, subscription:} }
  end

  describe "queue routing" do
    context "when the organization is targeted for the dedicated queue" do
      before { stub_const("Utils::DedicatedWorkerConfig::ORGANIZATION_IDS", [organization.id]) }

      it "routes to the dedicated queue" do
        expect { described_class.perform_later(alert:, subscription:) }
          .to have_enqueued_job(described_class).on_queue("dedicated_alerts")
      end
    end
  end

  describe "#perform" do
    before do
      allow(UsageMonitoring::ProcessLifetimeUsageAlertService).to receive(:call!)
    end

    it "calls ProcessLifetimeUsageAlertService with the alert and subscription" do
      described_class.perform_now(alert:, subscription:)
      expect(UsageMonitoring::ProcessLifetimeUsageAlertService).to have_received(:call!).with(alert:, subscription:)
    end
  end
end
