# frozen_string_literal: true

require "rails_helper"

RSpec.describe Webhooks::UsageMonitoring::AlertResolvedService do
  subject(:webhook_service) { described_class.new(object: resolved_alert) }

  let(:resolved_alert) do
    create(:triggered_alert, kind: :resolved, in_alarm_thresholds: ["warn"], fully_resolved: false)
  end

  describe ".call" do
    it_behaves_like "creates webhook", "alert.resolved", "resolved_alert"

    context "with a catalog wallet alert's history row" do
      let(:customer) { create(:customer, external_id: "acme", currency: "USD") }
      let(:catalog_wallet) { create(:catalog_wallet, organization: customer.organization, customer:, contract: create(:contract, customer:, external_id: "ctr_123", code: "main"), code: "prepaid", currency: "USD") }
      let(:alert) { create(:catalog_wallet_alert, organization: customer.organization, catalog_wallet:, alert_type: "balance", code: "low_balance", name: "Low balance") }
      let(:resolved_alert) do
        create(
          :catalog_wallet_triggered_alert,
          alert:,
          kind: :resolved,
          resolution_reason: :threshold_removed,
          current_value: 1_500,
          previous_value: 1_500,
          crossed_thresholds: [{code: "low", value: BigDecimal(2_000), recurring: false}],
          in_alarm_thresholds: [],
          fully_resolved: true,
          triggered_at: Time.zone.parse("2026-11-22 12:00:00")
        )
      end

      it "sends its v2 body under the same event" do
        webhook_service.call

        expect(Webhook.order(created_at: :desc).first.payload).to eq(
          "webhook_type" => "alert.resolved",
          "object_type" => "resolved_alert",
          "organization_id" => customer.organization_id,
          "resolved_alert" => {
            "lago_id" => resolved_alert.id,
            "lago_alert_id" => alert.id,
            "alert_code" => "low_balance",
            "alert_name" => "Low balance",
            "alert_type" => "balance",
            "lago_wallet_id" => catalog_wallet.id,
            "wallet_code" => "prepaid",
            "currency" => "USD",
            "lago_contract_id" => catalog_wallet.contract_id,
            "external_contract_id" => "ctr_123",
            "contract_code" => "main",
            "external_customer_id" => "acme",
            "current_value" => "1500.0",
            "previous_value" => "1500.0",
            "recovered_thresholds" => [{"code" => "low", "value" => "2000.0", "recurring" => false}],
            "in_alarm_thresholds" => [],
            "fully_resolved" => true,
            "reason" => "threshold_removed",
            "resolved_at" => "2026-11-22T12:00:00Z"
          }
        )
      end
    end

    context "with a contract alert's history row" do
      let(:customer) { create(:customer, external_id: "acme", currency: "USD") }
      let(:contract) { create(:contract, customer:, external_id: "ctr_123") }
      let(:product) { create(:product, organization: customer.organization, code: "llm_tokens") }
      let(:alert) { create(:contract_usage_units_alert, organization: customer.organization, contract_external_id: "ctr_123", product:, code: "tokens", name: "Tokens") }
      let(:resolved_alert) do
        create(
          :contract_triggered_alert,
          alert:,
          contract:,
          kind: :resolved,
          resolution_reason: :threshold_updated,
          current_value: 1_500,
          previous_value: 1_500,
          crossed_thresholds: [{code: "warn", value: BigDecimal(1_200), recurring: false}],
          in_alarm_thresholds: [],
          fully_resolved: true,
          triggered_at: Time.zone.parse("2026-11-22 12:00:00")
        )
      end

      it "sends its v2 body under the same event" do
        webhook_service.call

        expect(Webhook.order(created_at: :desc).first.payload).to eq(
          "webhook_type" => "alert.resolved",
          "object_type" => "resolved_alert",
          "organization_id" => customer.organization_id,
          "resolved_alert" => {
            "lago_id" => resolved_alert.id,
            "lago_alert_id" => alert.id,
            "alert_code" => "tokens",
            "alert_name" => "Tokens",
            "alert_type" => "usage_units",
            "currency" => nil,
            "lago_contract_id" => contract.id,
            "external_contract_id" => "ctr_123",
            "external_customer_id" => "acme",
            "current_value" => "1500.0",
            "previous_value" => "1500.0",
            "scope" => [{"type" => "contract", "product_code" => "llm_tokens", "with_product_filters" => false}],
            "recovered_thresholds" => [{"code" => "warn", "value" => "1200.0", "recurring" => false}],
            "in_alarm_thresholds" => [],
            "fully_resolved" => true,
            "reason" => "threshold_updated",
            "resolved_at" => "2026-11-22T12:00:00Z"
          }
        )
      end
    end
  end
end
