# frozen_string_literal: true

require "rails_helper"

RSpec.describe UsageMonitoring::DestroyAlertService do
  describe ".call" do
    subject(:result) { described_class.call(alert:) }

    let(:alert) { create(:alert, thresholds: [1, 2, 50]) }

    it "discards the alert" do
      expect(result).to be_success
      expect(result.alert).to be_discarded
      expect(result.alert.thresholds.count).to eq 0
    end

    it "locks the alert row before deleting its thresholds" do
      statements = capture_sql { result }

      locked_alert = statements.index { it.include?("usage_monitoring_alerts") && it.include?("FOR UPDATE") }
      deleted_thresholds = statements.index { it.start_with?("DELETE FROM \"usage_monitoring_alert_thresholds\"") }

      expect(locked_alert).not_to be_nil
      expect(deleted_thresholds).not_to be_nil
      expect(locked_alert).to be < deleted_thresholds
    end
  end
end
