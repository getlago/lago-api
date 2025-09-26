# frozen_string_literal: true

require "rails_helper"

RSpec.describe UsageMonitoring::CreateAlertService do
  describe ".call" do
    subject(:result) { described_class.call(organization:, subscription:, params:) }

    let(:organization) { create(:organization, premium_integrations:) }
    let(:premium_integrations) { [] }
    let(:thresholds) { [{code: "warning", value: 80}, {code: "critical", value: 120}] }
    let(:params) { {alert_type: "current_usage_amount", name: "Main", thresholds:, code: "first", billable_metric_id: billable_metric&.id} }
    let(:subscription) { create(:subscription, organization:) }
    let(:billable_metric) { nil }

    it "creates a new alert" do
      expect(result).to be_success

      alert = result.alert
      expect(alert.organization_id).to eq(organization.id)
      expect(alert.subscription_external_id).to eq(subscription.external_id)
      expect(alert.billable_metric).to be_nil
      expect(alert.alert_type).to eq("current_usage_amount")
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
        create(:billable_metric_current_usage_amount_alert, organization:, code: "first", subscription_external_id: subscription.external_id)
        expect(result).to be_failure
        expect(result.error.messages[:code]).to eq(["value_already_exist"])
      end
    end

    context "with billable_metric_current_usage_amount type" do
      let(:params) { {alert_type: "billable_metric_current_usage_amount", billable_metric_id: billable_metric.id, thresholds:, code: "first"} }
      let(:billable_metric) { create(:billable_metric, organization:) }

      it do
        expect(result).to be_success

        alert = result.alert
        expect(alert.billable_metric_id).to eq billable_metric.id
        expect(alert.alert_type).to eq("billable_metric_current_usage_amount")
      end

      context "when billable_metric is missing" do
        let(:params) { {alert_type: "billable_metric_current_usage_amount", thresholds:, code: "first"} }
        let(:billable_metric) { nil }

        it "returns a record validation failure result" do
          expect(result).to be_failure
          expect(result.error.messages[:billable_metric]).to eq(["value_is_mandatory"])
        end
      end

      context "when billable_metric is not found" do
        let(:params) { {alert_type: "billable_metric_current_usage_amount", billable_metric_code: "not,found", thresholds:, code: "first"} }
        let(:billable_metric) { nil }

        it "returns a record validation failure result" do
          expect(result).to be_failure
          expect(result.error.message).to eq "billable_metric_not_found"
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
      let(:params) { {alert_type: "current_usage_amount", code: nil, thresholds: [{value: nil}]} }

      it "returns a validation failure result" do
        expect(result).to be_failure
        expect(result.error.messages[:code]).to eq(["value_is_mandatory"])
      end
    end

    context "when alert_type is blank" do
      let(:params) { {alert_type: nil, code: "ok", thresholds: [{value: nil}]} }

      it "returns a validation failure result" do
        expect(result).to be_failure
        expect(result.error.messages[:alert_type]).to eq(%w[value_is_mandatory value_is_invalid])
      end
    end

    context "when thresholds are blank" do
      let(:params) { {alert_type: "current_usage_amount", code: "ok", thresholds: []} }

      it "returns a validation failure result" do
        expect(result).to be_failure
        expect(result.error.messages[:thresholds]).to include("value_is_mandatory")
      end
    end

    context "when thresholds have duplicate values" do
      let(:params) { {alert_type: "current_usage_amount", code: "ok", thresholds: [{value: 1}, {value: 1}]} }

      it "returns a validation failure result" do
        expect(result).to be_failure
        expect(result.error.messages[:thresholds]).to include("duplicate_threshold_values")
      end
    end

    context "when code is missing" do
      let(:params) { {alert_type: "current_usage_amount", thresholds:, code: nil} }

      it "returns a record validation failure result" do
        expect(result).to be_failure
        expect(result.error.messages[:code]).to eq(["value_is_mandatory"])
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

    context "when creating lifetime_usage alert" do
      let(:params) { {alert_type: "lifetime_usage_amount", thresholds:, code: "first"} }

      around { |test| lago_premium!(&test) }

      context "when organization using lifetime usage" do
        let(:premium_integrations) { [] }

        it "returns a record validation failure result" do
          expect(result).to be_failure
          expect(result.error.messages[:alert_type]).to eq ["feature_not_available"]
        end
      end

      context "when organization does not use lifetime usage" do
        let(:premium_integrations) { ["lifetime_usage"] }

        it "creates the alert" do
          expect(result).to be_success
          expect(result.alert).to be_persisted
          expect(result.alert.alert_type).to eq "lifetime_usage_amount"
        end
      end
    end
  end
end
