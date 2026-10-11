# frozen_string_literal: true

require "rails_helper"

RSpec.describe UsageMonitoring::BillableMetricCurrentUsageUnitsAlert do
  subject { alert.find_value(current_usage) }

  let(:alert) { create(:billable_metric_current_usage_units_alert, subscription_external_id: "test") }
  let(:current_usage) { instance_double(SubscriptionUsage, amount_cents: 100, fees:) }
  let(:charge) { create(:standard_charge, billable_metric: alert.billable_metric) }
  let(:fees) do
    [
      create(:charge_fee, charge:, units: 8),
      create(:charge_fee, charge:, units: 4), # will ensure that we're using max not min
      create(:charge_fee, units: 12) # ensure that we look only within correct charge fees
    ]
  end

  describe "#find_value" do
    it "returns biggest units among fees related to the alert's billable metric" do
      expect(subject).to eq(8)
    end
  end

  describe "#window_resets_each_period?" do
    let(:alert) do
      create(:billable_metric_current_usage_units_alert, subscription_external_id: "test", billable_metric:)
    end

    context "when the metric is not recurring" do
      let(:billable_metric) { create(:sum_billable_metric) }

      it "resets" do
        expect(alert.window_resets_each_period?(nil)).to be true
      end
    end

    context "when the metric is recurring" do
      let(:billable_metric) { create(:sum_billable_metric, :recurring) }

      it "keeps the baseline" do
        expect(alert.window_resets_each_period?(nil)).to be false
      end
    end
  end
end
