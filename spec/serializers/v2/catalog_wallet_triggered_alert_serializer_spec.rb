# frozen_string_literal: true

require "rails_helper"

RSpec.describe ::V2::CatalogWalletTriggeredAlertSerializer do
  subject(:serializer) { described_class.new(triggered_alert.reload, root_name: "triggered_alert") }

  let_it_be(:organization) { create(:organization) }
  let_it_be(:customer) { create(:customer, organization:, external_id: "acme", currency: "USD") }
  let_it_be(:contract) { create(:contract, customer:, external_id: "ctr_123", code: "main") }
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
      triggered_at: Time.zone.parse("2026-11-22 12:00:00.123456")
    )
  end

  it "renders the alert, its wallet and the values, at whole seconds" do
    expect(JSON.parse(serializer.to_json)).to eq(
      "triggered_alert" => {
        "lago_id" => triggered_alert.id,
        "lago_alert_id" => alert.id,
        "alert_code" => "low_balance",
        "alert_name" => "Low balance",
        "alert_type" => "balance",
        "lago_wallet_id" => catalog_wallet.id,
        "wallet_code" => "prepaid",
        "currency" => "USD",
        "lago_contract_id" => contract.id,
        "external_contract_id" => "ctr_123",
        "contract_code" => "main",
        "external_customer_id" => "acme",
        "current_value" => "1500.0",
        "previous_value" => "3000.0",
        "crossed_thresholds" => [{"code" => "low", "value" => "2000.0", "recurring" => false}],
        "triggered_at" => "2026-11-22T12:00:00Z"
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
        "alert_code" => "low_balance",
        "alert_name" => "Low balance",
        "alert_type" => "balance"
      )
    end
  end
end
