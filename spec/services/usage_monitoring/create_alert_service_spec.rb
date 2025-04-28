# frozen_string_literal: true

require "rails_helper"

RSpec.describe UsageMonitoring::CreateAlertService do
  describe ".call" do
    subject(:result) { described_class.call(organization:, subscription:, params:, billable_metric:) }

    let(:organization) { create(:organization) }
    let(:thresholds) { [{code: "warning", value: 80}, {code: "critical", value: 120}] }
    let(:params) { {alert_type: "usage_amount", name: "Main", thresholds:, code: "first"} }
    let(:subscription) { create(:subscription, organization:) }
    let(:billable_metric) { nil }

    it "creates a new alert" do
      expect(result).to be_success

      alert = result.alert
      expect(alert.organization_id).to eq(organization.id)
      expect(alert.subscription_external_id).to eq(subscription.external_id)
      expect(alert.billable_metric).to be_nil
      expect(alert.alert_type).to eq("usage_amount")
      expect(alert.name).to eq("Main")
      expect(alert.code).to eq("first")

      expect(alert.thresholds.map(&:code)).to eq %w[warning critical]
      expect(alert.thresholds.map(&:value)).to eq [80, 120]
      expect(alert.thresholds.map(&:recurring)).to all(be_falsey)
      expect(alert.thresholds.size).to eq(2)
    end

    context "with recurring threshold" do
      let(:thresholds) { [{value: 80}, {code: "warning", value: 100}, {value: 32, recurring: true}] }

      it "creates a new alert" do
        expect(result).to be_success
        expect(result.alert.thresholds.pluck(:code, :value, :recurring)).to contain_exactly(
          [nil, 80, false], ["warning", 100, false], [nil, 32, true]
        )
      end
    end

    context "when code already exists" do
      it "returns a record validation failure result" do
        create(:billable_metric_usage_amount_alert, organization:, code: "first", subscription_external_id: subscription.external_id)
        expect(result).to be_failure
        expect(result.error.message).to include("code_already_exists")
      end
    end

    context "with billable_metric_usage_amount type" do
      let(:params) { {alert_type: "billable_metric_usage_amount", thresholds:, code: "first"} }
      let(:billable_metric) { create(:billable_metric, organization:) }

      it do
        expect(result).to be_success

        alert = result.alert
        expect(alert.billable_metric_id).to eq billable_metric.id
        expect(alert.alert_type).to eq("billable_metric_usage_amount")
      end

      context "when billable_metric is missing" do
        let(:params) { {alert_type: "billable_metric_usage_amount", thresholds:, code: "first"} }
        let(:billable_metric) { nil }

        it "returns a record validation failure result" do
          expect(result).to be_failure
          expect(result.error.message).to include("is required for `billable_metric_usage_amount` alert type")
        end
      end
    end

    context "when the subscription is not active" do
      let(:subscription) { create(:subscription, :terminated) }

      it do
        expect(result).to be_success
      end
    end

    context "when code is blank" do
      let(:params) { {alert_type: "usage", code: nil, thresholds: [1]} }

      it "returns a validation failure result" do
        expect(result).to be_failure
        expect(result.error.message).to include("code_must_be_present")
      end
    end

    context "when alert_type is blank" do
      let(:params) { {alert_type: nil, code: "ok", thresholds: [1]} }

      it "returns a validation failure result" do
        expect(result).to be_failure
        expect(result.error.message).to include("alert_type_must_be_present")
      end
    end

    context "when thresholds are blank" do
      let(:params) { {alert_type: "usage", code: "ok", thresholds: []} }

      it "returns a validation failure result" do
        expect(result).to be_failure
        expect(result.error.message).to include("thresholds_must_be_present")
      end
    end

    context "when code is missing" do
      let(:params) { {alert_type: "usage_amount", thresholds:, code: nil} }

      it "returns a record validation failure result" do
        expect(result).to be_failure
        expect(result.error.message).to include("code_must_be_present")
      end
    end

    context "when alert_type is invalid" do
      let(:params) { {alert_type: "yolo", thresholds:, code: "first"} }

      it "returns a record validation failure result" do
        expect(result).to be_failure
        expect(result.error.message).to include("invalid_type")
      end
    end

    context "with too many thresholds" do
      let(:thresholds) do
        Array.new(21) do |i|
          {code: "warning#{i}", value: 10 + i}
        end
      end

      it "returns a record validation failure result" do
        expect(result).to be_failure
        expect(result.error.message).to include("too_many_thresholds")
      end
    end
  end
end
