# frozen_string_literal: true

require "rails_helper"

RSpec.describe UsageMonitoring::ProcessLifetimeUsageAlertJob do
  let(:alert) { create(:billable_metric_lifetime_usage_units_alert) }

  describe "unique job behavior" do
    around do |example|
      ActiveJob::Uniqueness.reset_manager!
      example.run
      ActiveJob::Uniqueness.test_mode!
    end

    it "does not enqueue duplicate jobs" do
      expect do
        described_class.perform_later(alert.id)
        described_class.perform_later(alert.id)
      end.to change { enqueued_jobs.count }.by(1) # rubocop:disable RSpec/ExpectChange
    end
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
