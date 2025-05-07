# frozen_string_literal: true

require "rails_helper"

RSpec.describe UsageMonitoring::UpdateAlertService do
  subject(:result) { described_class.call(alert:, params:, billable_metric:) }

  let(:alert) { create(:alert, thresholds: [1, 50]) }
  let(:billable_metric) { nil }

  describe "#call" do
    let(:params) do
      {code: "new_code", name: "Renamed", thresholds: [
        {value: 40},
        {code: :warn, value: 100},
        {code: :critical, value: 200, recurring: true}
      ]}
    end

    it "updates the alert" do
      expect(result).to be_success
      expect(result.alert).to eq(alert)
      expect(alert.reload.name).to eq("Renamed")
      expect(alert.reload.code).to eq("new_code")
      expect(alert.reload.thresholds.map(&:value)).to eq [40, 100, 200]
      expect(alert.reload.thresholds.map(&:code)).to eq [nil, "warn", "critical"]
    end

    context "with a billable metric" do
      let(:alert) { create(:billable_metric_usage_amount_alert, thresholds: [50]) }
      let(:billable_metric) { create(:billable_metric, organization: alert.organization) }

      it "updates the alert" do
        expect(result).to be_success
        expect(result.alert.billable_metric_id).to eq(billable_metric.id)
      end

      context "when alert is not billable_metric_usage_amount" do
        let(:alert) { create(:usage_amount_alert, thresholds: [50]) }

        it "returns an error" do
          expect(result).not_to be_success
          expect(result.error.message).to include("invalid_alert_type")
        end
      end
    end
  end
end
