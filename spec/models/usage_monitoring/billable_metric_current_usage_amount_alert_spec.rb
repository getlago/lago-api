# frozen_string_literal: true

require "rails_helper"

RSpec.describe UsageMonitoring::BillableMetricCurrentUsageAmountAlert, type: :model do
  subject { alert.find_value(current_usage) }

  let(:alert) { create(:billable_metric_current_usage_amount_alert, subscription_external_id: "test") }
  let(:current_usage) { instance_double(SubscriptionUsage, amount_cents: 100, fees:) }
  let(:charge) { create(:standard_charge, billable_metric: alert.billable_metric) }
  let(:fees) do
    [
      create(:charge_fee, charge:, amount_cents: 8),
      create(:charge_fee, charge:, amount_cents: 4), # will ensure that we're using max not min
      create(:charge_fee, amount_cents: 12) # ensure that we look only within correct charge fees
    ]
  end

  describe "#find_value" do
    it "returns biggest units among fees related to the alert's billable metric" do
      expect(subject).to eq(8)
    end
  end
end
