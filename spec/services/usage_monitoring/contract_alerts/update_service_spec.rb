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
    scope: [{type: "contract", product_code: "llm_tokens"}]
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
    let(:params) { {code: "new_code", alert_type: "usage_units", scope: []} }

    it "returns value_cannot_be_changed on each" do
      expect(result.error.messages).to eq({
        code: ["value_cannot_be_changed"],
        alert_type: ["value_cannot_be_changed"],
        scope: ["value_cannot_be_changed"]
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

    it "sends a webhook that renders the resolution" do
      perform_enqueued_jobs(only: SendWebhookJob) { result }

      resolved = alert.all_triggered_alerts.resolved.sole
      expect(Webhook.where(webhook_type: "alert.resolved").sole.payload["resolved_alert"]).to include(
        "lago_id" => resolved.id,
        "lago_alert_id" => alert.id,
        "lago_contract_id" => contract.id,
        "external_contract_id" => contract.external_id,
        "recovered_thresholds" => [{"code" => "warn", "value" => "50.0", "recurring" => false}],
        "reason" => "threshold_updated"
      )
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

  context "with a premium license", :premium do
    it "tracks the active contract once the edit is committed, so the next tick evaluates the new thresholds" do
      ApplicationRecord.transaction do
        expect(result).to be_success
        expect(UsageMonitoring::ContractActivity.count).to eq(0)
      end

      expect(UsageMonitoring::ContractActivity.sole).to have_attributes(organization_id: organization.id, contract_id: contract.id, enqueued: false)
    end

    context "with only a name" do
      let(:params) { {name: "Renamed"} }

      it "tracks the active contract" do
        expect(result).to be_success
        expect(UsageMonitoring::ContractActivity.sole.contract_id).to eq(contract.id)
      end
    end

    context "with a pending replacement on the same external id" do
      before { create(:contract, :pending, organization:, customer:, external_id: contract.external_id) }

      it "tracks the active contract only" do
        expect(result).to be_success
        expect(UsageMonitoring::ContractActivity.sole.contract_id).to eq(contract.id)
      end
    end

    context "when only a pending contract is live" do
      let(:contract) { create(:contract, :pending, organization:, customer:) }

      it "does not track it, as it is not evaluated before it is active" do
        expect(result).to be_success
        expect(UsageMonitoring::ContractActivity.count).to eq(0)
      end
    end

    context "when the only contract on the external id is terminated" do
      let(:contract) { create(:contract, :terminated, organization:, customer:) }

      it "does not track it" do
        expect(result).to be_failure
        expect(UsageMonitoring::ContractActivity.count).to eq(0)
      end
    end

    context "when the alert is deleted while the update waits for its lock" do
      before do
        create(:contract_usage_units_alert, organization:, contract_external_id: contract.external_id)
        UsageMonitoring::DestroyAlertService.call(alert: UsageMonitoring::ContractAlert.find(alert.id))
      end

      it "does not track the contract" do
        expect(result).to be_failure
        expect(UsageMonitoring::ContractActivity.count).to eq(0)
      end
    end

    context "with invalid thresholds" do
      let(:params) { {thresholds: [{value: 10}, {value: 10}]} }

      it "does not track the contract" do
        expect(result).to be_failure
        expect(UsageMonitoring::ContractActivity.count).to eq(0)
      end
    end

    context "without the contract_alerts flag" do
      let(:other_organization) { create(:organization, feature_flags: %w[product_catalog]) }
      let(:contract) { create(:contract, organization: other_organization, customer: create(:customer, organization: other_organization)) }
      let(:alert) do
        create(:contract_alert, organization: other_organization, contract_external_id: contract.external_id, name: "Spend", thresholds: nil)
      end

      it "does not track the contract" do
        expect(result).to be_success
        expect(UsageMonitoring::ContractActivity.count).to eq(0)
      end
    end
  end

  context "without a premium license" do
    it "does not track the contract" do
      expect(result).to be_success
      expect(UsageMonitoring::ContractActivity.count).to eq(0)
    end
  end
end
