# frozen_string_literal: true

require "rails_helper"

RSpec.describe UsageMonitoring::BillableMetricUsageUnitsAlert, type: :model do
  let(:alert) { create(:billable_metric_usage_units_alert) }
  let(:subscription) { create(:subscription) }
  let(:charge) { create(:standard_charge, plan: subscription.plan, billable_metric: alert.billable_metric) }
  let(:fees) do
    [
      create(:charge_fee, charge: charge, amount_cents: 12, units: 8),
      create(:charge_fee)
    ]
  end

  describe "#find_value" do
    it do
      charge
      current_usage = double(amount_cents: 100, fees:) # rubocop:disable RSpec/VerifiedDoubles
      expect(alert.find_value(current_usage)).to eq(8)
    end
  end
end
