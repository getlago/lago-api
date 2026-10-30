# frozen_string_literal: true

require "rails_helper"

RSpec.describe UsageMonitoring::CurrentUsageAmountAlert do
  let(:alert) { create(:usage_current_amount_alert) }
  let(:subscription) { create(:subscription) }

  describe "#find_value" do
    it do
      current_usage = double(amount_cents: 100) # rubocop:disable RSpec/VerifiedDoubles
      expect(alert.find_value(current_usage)).to eq(100)
    end
  end

  describe "#window_resets_each_period?" do
    let(:plan) { create(:plan) }
    let(:subscription) { create(:subscription, plan:) }
    let(:recurring_metric) { create(:sum_billable_metric, :recurring, organization: plan.organization) }
    let(:metered_metric) { create(:sum_billable_metric, organization: plan.organization) }

    context "without any charge" do
      it "resets" do
        expect(alert.window_resets_each_period?(subscription)).to be true
      end
    end

    context "with only non-recurring charges" do
      before { create(:standard_charge, plan:, billable_metric: metered_metric) }

      it "resets" do
        expect(alert.window_resets_each_period?(subscription)).to be true
      end
    end

    context "with recurring and non-recurring charges" do
      before do
        create(:standard_charge, plan:, billable_metric: recurring_metric)
        create(:standard_charge, plan:, billable_metric: metered_metric)
      end

      it "resets, because the non-recurring part of the amount restarts" do
        expect(alert.window_resets_each_period?(subscription)).to be true
      end
    end

    context "with only recurring charges" do
      before { create(:standard_charge, plan:, billable_metric: recurring_metric) }

      it "keeps the baseline" do
        expect(alert.window_resets_each_period?(subscription)).to be false
      end
    end

    context "when the only non-recurring charge was discarded" do
      before do
        create(:standard_charge, plan:, billable_metric: recurring_metric)
        create(:standard_charge, plan:, billable_metric: metered_metric).discard!
      end

      it "keeps the baseline" do
        expect(alert.window_resets_each_period?(subscription)).to be false
      end
    end
  end
end
