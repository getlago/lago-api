# frozen_string_literal: true

require "rails_helper"

RSpec.describe UsageMonitoring::UpdateAlertService do
  subject(:result) { described_class.call(alert:, params:) }

  let(:organization) { create(:organization, premium_integrations:) }
  let(:premium_integrations) { [] }
  let(:alert) { create(:alert, thresholds: [1, 50], organization: organization) }

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

    context "with a billable_metric_id" do
      let(:alert) { create(:billable_metric_current_usage_amount_alert, thresholds: [50]) }
      let(:billable_metric) { create(:billable_metric, organization: alert.organization) }
      let(:params) do
        {code: "new_code", name: "Renamed", billable_metric_id: billable_metric.id, thresholds: [
          {value: 40},
          {code: :warn, value: 100},
          {code: :critical, value: 200, recurring: true}
        ]}
      end

      it "updates the alert" do
        expect(result).to be_success
        expect(result.alert.billable_metric_id).to eq(billable_metric.id)
      end

      context "when alert is not billable_metric_current_usage_amount" do
        let(:alert) { create(:usage_current_amount_alert, thresholds: [50]) }

        it "returns an error" do
          expect(result).not_to be_success
          expect(result.error.messages[:billable_metric]).to eq ["value_must_be_blank"]
        end
      end

      context "when billable_metric is not found" do
        let(:params) { {code: "new_code", billable_metric_id: "not-found"} }

        it "returns a record validation failure result" do
          expect(result).to be_failure
          expect(result.error.message).to eq "billable_metric_not_found"
        end
      end

      context "when code already exists" do
        it "returns a record validation failure result" do
          create(:billable_metric_current_usage_amount_alert, organization: alert.organization, code: "new_code", subscription_external_id: alert.subscription_external_id)
          expect(result).to be_failure
          expect(result.error.messages[:code]).to eq(["value_already_exist"])
        end
      end
    end

    context "with too many thresholds" do
      let(:params) do
        {
          thresholds: Array.new(21) do |i|
            {code: "warning#{i}", value: 10 + i}
          end
        }
      end

      it "returns a record validation failure result" do
        expect(result).to be_failure
        expect(result.error.message).to include("too_many_thresholds")
      end
    end

    context "when thresholds have duplicate values" do
      let(:params) { {thresholds: [{value: 1}, {value: 1}]} }

      it "returns a validation failure result" do
        expect(result).to be_failure
        expect(result.error.messages[:thresholds]).to include("duplicate_threshold_values")
      end
    end
  end
end
