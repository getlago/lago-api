# frozen_string_literal: true

require "rails_helper"

RSpec.describe UsageMonitoring::ProcessLifetimeUsageAlertJob do
  describe "#perform" do
    let(:alert) { create(:billable_metric_lifetime_usage_units_alert) }

    before do
      allow(UsageMonitoring::ProcessLifetimeUsageAlertService).to receive(:call!)
    end

    it "calls ProcessLifetimeUsageAlertService with the alert", :premium do
      described_class.perform_now(alert.id)
      expect(UsageMonitoring::ProcessLifetimeUsageAlertService).to have_received(:call!).with(alert:)
    end

    context "when license is not premium" do
      it "does not call the service" do
        described_class.perform_now(alert.id)
        expect(UsageMonitoring::ProcessLifetimeUsageAlertService).not_to have_received(:call!)
      end
    end
  end
end
