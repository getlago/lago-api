# frozen_string_literal: true

require "rails_helper"

RSpec.describe ::V1::UsageMonitoring::CatalogWalletResolvedAlertSerializer do
  subject(:serializer) { described_class.new(resolved_alert.reload, root_name: "resolved_alert") }

  let_it_be(:organization) { create(:organization) }
  let_it_be(:customer) { create(:customer, organization:, external_id: "acme") }
  let_it_be(:contract) { create(:contract, customer:, external_id: "ctr_123") }
  let_it_be(:catalog_wallet) { create(:catalog_wallet, organization:, customer:, contract:, code: "prepaid", currency: "USD") }

  let(:alert) { create(:catalog_wallet_alert, organization:, catalog_wallet:, alert_type: "ongoing_balance", code: "low_ongoing", name: "Low ongoing") }
  let(:resolved_alert) do
    create(
      :catalog_wallet_triggered_alert,
      organization:,
      alert:,
      kind: "resolved",
      resolution_reason: "threshold_removed",
      current_value: 1_500,
      previous_value: 1_500,
      crossed_thresholds: [{code: "low", value: BigDecimal(2_000), recurring: false}],
      in_alarm_thresholds: ["critical"],
      fully_resolved: false,
      triggered_at: Time.zone.parse("2026-11-22 12:00:00")
    )
  end

  it "renders the v1 keys, the contract ones and the wallet's code and currency" do
    expect(JSON.parse(serializer.to_json)).to eq(
      "resolved_alert" => {
        "lago_id" => resolved_alert.id,
        "lago_organization_id" => organization.id,
        "lago_alert_id" => alert.id,
        "lago_subscription_id" => nil,
        "external_subscription_id" => nil,
        "lago_wallet_id" => catalog_wallet.id,
        "wallet_code" => "prepaid",
        "currency" => "USD",
        "lago_contract_id" => contract.id,
        "external_contract_id" => "ctr_123",
        "product_code" => nil,
        "product_filter_code" => nil,
        "applies_to" => nil,
        "external_customer_id" => "acme",
        "billable_metric_code" => nil,
        "alert_name" => "Low ongoing",
        "alert_code" => "low_ongoing",
        "alert_type" => "ongoing_balance",
        "current_value" => "1500.0",
        "previous_value" => "1500.0",
        "recovered_thresholds" => [{"code" => "low", "value" => "2000.0", "recurring" => false}],
        "in_alarm_thresholds" => ["critical"],
        "fully_resolved" => false,
        "reason" => "threshold_removed",
        "resolved_at" => "2026-11-22T12:00:00Z"
      }
    )
  end

  context "when the alert was deleted since" do
    before do
      resolved_alert
      alert.destroy!
    end

    it "renders the alert as its history kept it" do
      expect(JSON.parse(serializer.to_json)["resolved_alert"]).to include(
        "lago_alert_id" => alert.id,
        "alert_name" => "Low ongoing",
        "alert_code" => "low_ongoing",
        "alert_type" => "ongoing_balance"
      )
    end
  end
end
