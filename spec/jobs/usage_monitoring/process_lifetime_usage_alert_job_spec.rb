# frozen_string_literal: true

require "rails_helper"

RSpec.describe UsageMonitoring::ProcessLifetimeUsageAlertJob do
  let(:alert) { create(:billable_metric_lifetime_usage_units_alert) }

  it_behaves_like "a unique job" do
    let(:job_args) { [alert.id] }
  end

  describe "#perform" do
    before do
      allow(UsageMonitoring::ProcessLifetimeUsageAlertService).to receive(:call!)
    end

    it "calls ProcessLifetimeUsageAlertService with the alert" do
      described_class.perform_now(alert.id)
      expect(UsageMonitoring::ProcessLifetimeUsageAlertService).to have_received(:call!).with(alert:)
    end
  end
end
