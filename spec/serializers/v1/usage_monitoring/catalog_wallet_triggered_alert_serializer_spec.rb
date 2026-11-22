# frozen_string_literal: true

require "rails_helper"

RSpec.describe ::V1::UsageMonitoring::CatalogWalletTriggeredAlertSerializer do
  subject(:serializer) { described_class.new(triggered_alert.reload, root_name: "triggered_alert") }

  let_it_be(:organization) { create(:organization) }
  let_it_be(:customer) { create(:customer, organization:, external_id: "acme") }
  let_it_be(:contract) { create(:contract, customer:, external_id: "ctr_123") }
  let_it_be(:catalog_wallet) { create(:catalog_wallet, organization:, customer:, contract:, code: "prepaid", currency: "USD") }

  let(:alert) { create(:catalog_wallet_alert, organization:, catalog_wallet:, alert_type: "balance", code: "low_balance", name: "Low balance") }
  let(:triggered_alert) do
    create(
      :catalog_wallet_triggered_alert,
      organization:,
      alert:,
      current_value: 1_500,
      previous_value: 3_000,
      crossed_thresholds: [{code: "low", value: BigDecimal(2_000), recurring: false}],
      triggered_at: Time.zone.parse("2026-11-22 12:00:00")
    )
  end

  it "renders the v1 keys, the contract ones and the wallet's code and currency" do
    expect(JSON.parse(serializer.to_json)).to eq(
      "triggered_alert" => {
        "lago_id" => triggered_alert.id,
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
        "alert_name" => "Low balance",
        "alert_code" => "low_balance",
        "alert_type" => "balance",
        "current_value" => "1500.0",
        "previous_value" => "3000.0",
        "crossed_thresholds" => [{"code" => "low", "value" => "2000.0", "recurring" => false}],
        "triggered_at" => "2026-11-22T12:00:00Z",
        "subscription_external_id" => nil,
        "customer_external_id" => "acme"
      }
    )
  end

  context "when the alert was renamed since" do
    before do
      triggered_alert
      alert.update!(name: "Running low")
    end

    it "renders the alert's name" do
      expect(JSON.parse(serializer.to_json).dig("triggered_alert", "alert_name")).to eq("Running low")
    end
  end

  context "when the alert was deleted since" do
    before do
      triggered_alert
      alert.destroy!
    end

    it "renders the alert as its history kept it" do
      expect(JSON.parse(serializer.to_json)["triggered_alert"]).to include(
        "lago_alert_id" => alert.id,
        "alert_name" => "Low balance",
        "alert_code" => "low_balance",
        "alert_type" => "balance"
      )
    end
  end
end
