# frozen_string_literal: true

require "rails_helper"

RSpec.describe ::V2::ContractTriggeredAlertSerializer do
  subject(:serializer) { described_class.new(triggered_alert.reload, root_name: "triggered_alert") }

  let_it_be(:organization) { create(:organization) }
  let_it_be(:customer) { create(:customer, organization:, external_id: "acme", currency: "USD") }
  let_it_be(:contract) { create(:contract, customer:, external_id: "ctr_123") }
  let_it_be(:product) { create(:product, organization:, code: "llm_tokens") }
  let_it_be(:product_filter) { create(:product_filter, organization:, product:, code: "opus") }

  let(:alert) do
    create(:contract_usage_units_alert, organization:, contract_external_id: "ctr_123", product:, product_filter:, code: "opus_tokens", name: "Opus tokens")
  end
  let(:triggered_alert) do
    create(
      :contract_triggered_alert,
      organization:,
      alert:,
      contract:,
      current_value: 1_200_000,
      previous_value: 800_000,
      crossed_thresholds: [{code: "warn", value: BigDecimal(1_000_000), recurring: false}],
      triggered_at: Time.zone.parse("2026-11-22 12:00:00.123456")
    )
  end

  it "renders the alert, its scope, the contract evaluated and the values, at whole seconds" do
    expect(JSON.parse(serializer.to_json)).to eq(
      "triggered_alert" => {
        "lago_id" => triggered_alert.id,
        "lago_alert_id" => alert.id,
        "alert_code" => "opus_tokens",
        "alert_name" => "Opus tokens",
        "alert_type" => "usage_units",
        "currency" => nil,
        "lago_contract_id" => contract.id,
        "external_contract_id" => "ctr_123",
        "external_customer_id" => "acme",
        "current_value" => "1200000.0",
        "previous_value" => "800000.0",
        "scope" => [{"type" => "contract", "product_code" => "llm_tokens", "product_filter_codes" => ["opus"]}],
        "crossed_thresholds" => [{"code" => "warn", "value" => "1000000.0", "recurring" => false}],
        "triggered_at" => "2026-11-22T12:00:00Z"
      }
    )
  end

  context "with an amount alert on the whole contract" do
    let(:alert) do
      create(:contract_usage_amount_alert, organization:, contract_external_id: "ctr_123", code: "spend", name: "Spend")
    end

    it "renders the contract's currency and no product" do
      expect(JSON.parse(serializer.to_json)).to eq(
        "triggered_alert" => {
          "lago_id" => triggered_alert.id,
          "lago_alert_id" => alert.id,
          "alert_code" => "spend",
          "alert_name" => "Spend",
          "alert_type" => "usage_amount",
          "currency" => "USD",
          "lago_contract_id" => contract.id,
          "external_contract_id" => "ctr_123",
          "external_customer_id" => "acme",
          "current_value" => "1200000.0",
          "previous_value" => "800000.0",
          "scope" => [],
          "crossed_thresholds" => [{"code" => "warn", "value" => "1000000.0", "recurring" => false}],
          "triggered_at" => "2026-11-22T12:00:00Z"
        }
      )
    end
  end

  context "when the alert was deleted since" do
    before do
      triggered_alert
      alert.discard!
    end

    it "renders the deleted alert" do
      expect(JSON.parse(serializer.to_json)["triggered_alert"]).to include(
        "lago_alert_id" => alert.id,
        "alert_code" => "opus_tokens",
        "alert_name" => "Opus tokens",
        "alert_type" => "usage_units",
        "scope" => [{"type" => "contract", "product_code" => "llm_tokens", "product_filter_codes" => ["opus"]}]
      )
    end
  end
end
