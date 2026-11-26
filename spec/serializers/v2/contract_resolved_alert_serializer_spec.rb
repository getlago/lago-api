# frozen_string_literal: true

require "rails_helper"

RSpec.describe ::V2::ContractResolvedAlertSerializer do
  subject(:serializer) { described_class.new(resolved_alert.reload, root_name: "resolved_alert") }

  let_it_be(:organization) { create(:organization) }
  let_it_be(:customer) { create(:customer, organization:, external_id: "acme", currency: "EUR") }
  let_it_be(:contract) { create(:contract, customer:, external_id: "ctr_123") }
  let_it_be(:product) { create(:product, organization:, code: "llm_tokens") }

  let(:alert) do
    create(:contract_usage_amount_alert, organization:, contract_external_id: "ctr_123", product:, with_product_filters: true, code: "tokens_spend", name: "Tokens spend")
  end
  let(:resolved_alert) do
    create(
      :contract_triggered_alert,
      organization:,
      alert:,
      contract:,
      kind: "resolved",
      resolution_reason: "recovered",
      current_value: 1_500,
      previous_value: 2_500,
      crossed_thresholds: [{code: "high", value: BigDecimal(2_000), recurring: false}],
      in_alarm_thresholds: ["warn"],
      fully_resolved: false,
      triggered_at: Time.zone.parse("2026-11-22 12:00:00.123456")
    )
  end

  it "renders the alert, its scope, the contract evaluated, the values and the resolution, at whole seconds" do
    expect(JSON.parse(serializer.to_json)).to eq(
      "resolved_alert" => {
        "lago_id" => resolved_alert.id,
        "lago_alert_id" => alert.id,
        "alert_code" => "tokens_spend",
        "alert_name" => "Tokens spend",
        "alert_type" => "usage_amount",
        "currency" => "EUR",
        "lago_contract_id" => contract.id,
        "external_contract_id" => "ctr_123",
        "external_customer_id" => "acme",
        "current_value" => "1500.0",
        "previous_value" => "2500.0",
        "scope" => [{"type" => "contract", "product_code" => "llm_tokens", "with_product_filters" => true}],
        "recovered_thresholds" => [{"code" => "high", "value" => "2000.0", "recurring" => false}],
        "in_alarm_thresholds" => ["warn"],
        "fully_resolved" => false,
        "reason" => "recovered",
        "resolved_at" => "2026-11-22T12:00:00Z"
      }
    )
  end
end
