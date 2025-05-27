# frozen_string_literal: true

require "rails_helper"

RSpec.describe UsageMonitoring::Alert, type: :model do
  let(:alert) { create(:alert, code: "my-code", thresholds: [10, 30, 50], recurring_threshold: 100) }

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
        expect(alert.errors[:billable_metric]).to eq ["value_is_mandatory"]
      end
    end

    context "when code is not unique for a subscription" do
      it "raises an error" do
        expect {
          create(:billable_metric_usage_amount_alert, code: "my-code", subscription_external_id: alert.subscription_external_id, organization: alert.organization)
        }.to raise_error(ActiveRecord::RecordNotUnique)
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

  describe "#one_time_thresholds_values" do
    it "returns sorted unique threshold values" do
      expect(alert.one_time_thresholds_values).to eq([10, 30, 50])
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

    it "returns recurring threshold if crossed" do
      alert.previous_value = 33
      expect(alert.find_thresholds_crossed(351)).to eq([50, 150, 250, 350])
    end
  end

  describe "#formatted_crossed_thresholds" do
    it "returns formatted array of crossed thresholds matching given values" do
      result = alert.formatted_crossed_thresholds([10, 30])
      expect(result).to contain_exactly(
        {code: "warn10", value: 10, recurring: false},
        {code: "warn30", value: 30, recurring: false}
      )
    end

    context "when there is a non-recurring and a recurring threshold with the same value" do
      let(:alert) { create(:alert, code: "my-code", thresholds: [10, 15, 50], recurring_threshold: 10) }

      it "rejects the recurring threshold" do
        expect(alert.formatted_crossed_thresholds([10, 15])).to eq([
          {code: "warn10", recurring: false, value: 10},
          {code: "warn15", recurring: false, value: 15}
        ])
      end
    end

    context "when crossed thresholds isn't part of threshold values" do
      it "assumes it's recurring" do
        expect(alert.formatted_crossed_thresholds([40, 41, 42])).to eq([
          {code: "rec", recurring: true, value: 40},
          {code: "rec", recurring: true, value: 41},
          {code: "rec", recurring: true, value: 42}
        ])
      end
    end
  end

  describe "#find_value" do
    it "raises NotImplementedError" do
      expect { alert.find_value(double) }.to raise_error(NotImplementedError)
    end
  end
end
