# frozen_string_literal: true

require "rails_helper"

RSpec.describe UsageMonitoring::Alert, type: :model do
  let(:alert) { create(:alert, thresholds: [10, 30, 50]) }

  describe "associations" do
    it do
      expect(subject).to belong_to(:organization)
      expect(subject).to belong_to(:billable_metric).optional
      expect(subject).to have_many(:thresholds).class_name("UsageMonitoring::AlertThreshold")
        .with_foreign_key(:usage_monitoring_alert_id).dependent(:delete_all)
      expect(subject).to have_many(:triggered_alerts).class_name("UsageMonitoring::TriggeredAlert")
        .with_foreign_key(:usage_monitoring_alert_id)
    end
  end

  describe "validations" do
    context "when type requires billable_metric_id" do
      it do
        alert = build(:billable_metric_usage_amount_alert, billable_metric_id: nil)
        expect(alert).to be_invalid
        expect(alert.errors[:billable_metric_id]).to include("is required for `billable_metric_usage_amount` alert type")
      end
    end
  end

  describe ".find_sti_class" do
    it "returns correct constant for known alert types" do
      expect(described_class.find_sti_class("usage_amount")).to eq(UsageMonitoring::UsageAmountAlert)
      expect(described_class.find_sti_class("billable_metric_usage_amount")).to eq(UsageMonitoring::BillableMetricUsageAmountAlert)
    end

    it "raises KeyError for unknown alert type" do
      expect { described_class.find_sti_class("unknown_type") }.to raise_error(KeyError)
    end
  end

  describe ".sti_name" do
    it "returns correct sti_name for subclasses" do
      stub_const("UsageMonitoring::UsageAmountAlert", Class.new(described_class))
      stub_const("UsageMonitoring::BillableMetricUsageAmountAlert", Class.new(described_class))

      expect(UsageMonitoring::UsageAmountAlert.sti_name).to eq("usage_amount")
      expect(UsageMonitoring::BillableMetricUsageAmountAlert.sti_name).to eq("billable_metric_usage_amount")
    end
  end

  describe "#thresholds_values" do
    it "returns sorted unique threshold values" do
      expect(alert.thresholds_values).to eq([10, 30, 50])
    end
  end

  describe "#find_thresholds_crossed" do
    it "returns threshold values between previous_value and current (inclusive)" do
      alert.previous_value = 8
      expect(alert.find_thresholds_crossed(31)).to eq([10, 30])
      alert.previous_value = 31
      expect(alert.find_thresholds_crossed(60)).to eq([50])
    end

    it "returns empty array if no thresholds crossed" do
      alert.previous_value = 30
      expect(alert.find_thresholds_crossed(29)).to be_empty
    end
  end

  describe "#formatted_crossed_thresholds" do
    it "returns formatted array of crossed thresholds matching given values" do
      result = alert.formatted_crossed_thresholds([10, 30])
      expect(result).to contain_exactly({code: "warn10", value: 10}, {code: "warn30", value: 30})
    end

    it "returns empty array if no thresholds match" do
      expect(alert.formatted_crossed_thresholds([40])).to eq([])
    end
  end

  describe "#find_value" do
    it "raises NotImplementedError" do
      expect { alert.find_value(double) }.to raise_error(NotImplementedError)
    end
  end
end
