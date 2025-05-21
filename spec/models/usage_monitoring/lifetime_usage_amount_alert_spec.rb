# frozen_string_literal: true

require "rails_helper"

RSpec.describe UsageMonitoring::LifetimeUsageAmountAlert, type: :model do
  let(:alert) { create(:lifetime_usage_amount_alert) }
  let(:lifetime_usage) { create(:lifetime_usage, invoiced_usage_amount_cents: 6, current_usage_amount_cents: 3) }

  describe "#find_value" do
    it do
      expect(alert.find_value(lifetime_usage)).to eq(9)
    end
  end
end
