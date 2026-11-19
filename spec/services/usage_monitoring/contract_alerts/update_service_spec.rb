# frozen_string_literal: true

require "rails_helper"

RSpec.describe UsageMonitoring::ContractAlerts::UpdateService do
  subject(:result) { described_class.call(alert:, params:) }

  let_it_be(:organization) { create(:organization, feature_flags: %w[product_catalog contract_alerts]) }
  let_it_be(:customer) { create(:customer, organization:) }

  let(:contract) { create(:contract, organization:, customer:) }
  let(:alert) do
    create(:contract_alert, organization:, contract_external_id: contract.external_id, name: "Spend", thresholds: nil)
  end
  let(:params) { {name: "Renamed", thresholds: [{code: "warn", value: "40"}, {value: 100}]} }

  before do
    create(:contract_alert_threshold, alert:, organization:, code: "warn", value: 50, notify_on: %w[triggered resolved])
  end

  it "updates the name and replaces the thresholds" do
    expect(result).to be_success
    expect(result.alert).to eq(alert)

    alert.reload
    expect(alert.name).to eq("Renamed")
    expect(alert.thresholds.order(:value).pluck(:code, :value, :recurring, :notify_on)).to eq([
      ["warn", 40, false, %w[triggered resolved]],
      [nil, 100, false, %w[triggered]]
    ])
  end

  it "locks the alert while it replaces the thresholds" do
    allow(alert).to receive(:with_lock).and_call_original

    result

    expect(alert).to have_received(:with_lock)
  end

  context "with only a name" do
    let(:params) { {name: "Renamed"} }

    it "keeps the thresholds" do
      expect(result).to be_success
      expect(alert.reload.name).to eq("Renamed")
      expect(alert.thresholds.pluck(:code, :value)).to eq([["warn", 50]])
    end
  end

  context "with only thresholds" do
    let(:params) { {thresholds: [{value: 10}]} }

    it "keeps the name" do
      expect(result).to be_success
      expect(alert.reload.name).to eq("Spend")
      expect(alert.thresholds.pluck(:code, :value)).to eq([[nil, 10]])
    end
  end

  context "without an alert" do
    subject(:result) { described_class.call(alert: nil, params:) }

    it "returns a not found failure" do
      expect(result).to be_failure
      expect(result.error).to be_a(BaseService::NotFoundFailure)
      expect(result.error.error_code).to eq("alert_not_found")
    end
  end

  context "when the alert is deleted while the update waits for its lock" do
    before { UsageMonitoring::DestroyAlertService.call(alert: UsageMonitoring::ContractAlert.find(alert.id)) }

    it "returns a not found failure and recreates no thresholds" do
      expect(result).to be_failure
      expect(result.error).to be_a(BaseService::NotFoundFailure)
      expect(result.error.error_code).to eq("alert_not_found")
      expect(UsageMonitoring::ContractAlertThreshold.where(contract_alert_id: alert.id)).to be_empty
      expect(UsageMonitoring::ContractAlert.with_discarded.find(alert.id).name).to eq("Spend")
    end
  end

  {
    code: "new_code",
    alert_type: "usage_units",
    product_code: "llm_tokens",
    product_filter_code: "opus",
    product_id: SecureRandom.uuid,
    product_filter_id: SecureRandom.uuid
  }.each do |field, value|
    context "with #{field}" do
      let(:params) { {name: "Renamed"}.merge(field => value) }

      it "returns value_cannot_be_changed on #{field}" do
        expect(result).to be_failure
        expect(result.error.messages).to eq({field => ["value_cannot_be_changed"]})
        expect(alert.reload.name).to eq("Spend")
      end
    end
  end

  context "with several fields that cannot be changed" do
    let(:params) { {code: "new_code", alert_type: "usage_units", product_code: "llm_tokens"} }

    it "returns value_cannot_be_changed on each" do
      expect(result.error.messages).to eq({
        code: ["value_cannot_be_changed"],
        alert_type: ["value_cannot_be_changed"],
        product_code: ["value_cannot_be_changed"]
      })
    end
  end

  %i[terminated canceled].each do |status|
    context "when the only contract on the external id is #{status}" do
      let(:contract) { create(:contract, status, organization:, customer:) }

      it "returns contract_not_live" do
        expect(result).to be_failure
        expect(result.error).to be_a(BaseService::ForbiddenFailure)
        expect(result.error.code).to eq("contract_not_live")
        expect(alert.reload.name).to eq("Spend")
      end
    end
  end

  context "with invalid thresholds" do
    let(:params) { {thresholds: [{value: 10}, {value: 10}]} }

    it "returns the failure of the thresholds" do
      expect(result.error.messages).to eq({thresholds: ["duplicate_threshold_values"]})
      expect(alert.thresholds.pluck(:value)).to eq([50])
    end
  end

  [nil, []].each do |thresholds|
    context "with thresholds #{thresholds.inspect}" do
      let(:params) { {thresholds:} }

      it "returns a validation failure on thresholds" do
        expect(result.error.messages).to eq({thresholds: ["value_is_mandatory"]})
      end
    end
  end

  context "when an edit moves a threshold under the current usage" do
    let(:alert) do
      create(:contract_alert, organization:, contract_external_id: contract.external_id, previous_value: 40, thresholds: nil)
    end
    let(:params) { {thresholds: [{code: "warn", value: 30}]} }

    it "records it as seeded on the active contract, without a webhook" do
      expect(result).to be_success

      seeded = alert.all_triggered_alerts.sole
      expect(seeded).to have_attributes(kind: "seeded", contract:, current_value: 40, previous_value: 40)
      expect(seeded.crossed_thresholds).to eq([{"code" => "warn", "value" => "30.0", "recurring" => false}])
      expect(SendWebhookJob).not_to have_been_enqueued
    end
  end

  context "when an edit closes an alarm that was announced" do
    let(:alert) do
      create(:contract_alert, organization:, contract_external_id: contract.external_id, previous_value: 150, thresholds: nil)
    end
    let(:params) { {thresholds: [{code: "warn", value: 200}]} }

    before do
      create(
        :contract_triggered_alert,
        alert:,
        organization:,
        contract:,
        kind: :triggered,
        previous_value: 0,
        current_value: 150,
        crossed_thresholds: [{code: "warn", value: 50, recurring: false}]
      )
    end

    it "records the resolution on the active contract and sends alert.resolved" do
      expect(result).to be_success

      resolved = alert.all_triggered_alerts.resolved.sole
      expect(resolved).to have_attributes(
        contract:,
        resolution_reason: "threshold_updated",
        current_value: 150,
        previous_value: 150,
        fully_resolved: true,
        in_alarm_thresholds: []
      )
      expect(SendWebhookJob).to have_been_enqueued.once.with("alert.resolved", resolved)
    end

    context "with a pending replacement on the same external id" do
      before { create(:contract, :pending, organization:, customer:, external_id: contract.external_id) }

      it "records the resolution on the active contract" do
        expect(result).to be_success
        expect(alert.all_triggered_alerts.resolved.sole.contract).to eq(contract)
      end
    end

    context "when only a pending contract is live" do
      let(:contract) { create(:contract, :pending, organization:, customer:) }

      it "replaces the thresholds and records nothing" do
        expect(result).to be_success
        expect(alert.thresholds.pluck(:value)).to eq([200])
        expect(alert.all_triggered_alerts.resolved).to be_empty
        expect(SendWebhookJob).not_to have_been_enqueued
      end
    end
  end
end
