# frozen_string_literal: true

require "rails_helper"

RSpec.describe Webhooks::UsageMonitoring::AlertTriggeredService do
  subject(:webhook_service) { described_class.new(object: triggered_alert) }

  let(:triggered_alert) { create(:triggered_alert) }

  describe ".call" do
    it_behaves_like "creates webhook", "alert.triggered", "triggered_alert"

    context "with a catalog wallet alert's history row" do
      let(:customer) { create(:customer, external_id: "acme", currency: "USD") }
      let(:catalog_wallet) { create(:catalog_wallet, organization: customer.organization, customer:, contract: create(:contract, customer:, external_id: "ctr_123"), code: "prepaid", currency: "USD") }
      let(:alert) { create(:catalog_wallet_alert, organization: customer.organization, catalog_wallet:, alert_type: "balance", code: "low_balance", name: "Low balance") }
      let(:triggered_alert) do
        create(:catalog_wallet_triggered_alert, alert:, current_value: 1_500, previous_value: 3_000, crossed_thresholds: [{code: "low", value: BigDecimal(2_000), recurring: false}], triggered_at: Time.zone.parse("2026-11-22 12:00:00"))
      end

      it "sends its v2 body under the same event" do
        webhook_service.call

        expect(Webhook.order(created_at: :desc).first.payload).to eq(
          "webhook_type" => "alert.triggered",
          "object_type" => "triggered_alert",
          "organization_id" => customer.organization_id,
          "triggered_alert" => {
            "lago_id" => triggered_alert.id,
            "lago_alert_id" => alert.id,
            "alert_code" => "low_balance",
            "alert_name" => "Low balance",
            "alert_type" => "balance",
            "lago_wallet_id" => catalog_wallet.id,
            "wallet_code" => "prepaid",
            "currency" => "USD",
            "lago_contract_id" => catalog_wallet.contract_id,
            "external_contract_id" => "ctr_123",
            "external_customer_id" => "acme",
            "current_value" => "1500.0",
            "previous_value" => "3000.0",
            "crossed_thresholds" => [{"code" => "low", "value" => "2000.0", "recurring" => false}],
            "triggered_at" => "2026-11-22T12:00:00Z"
          }
        )
      end
    end

    context "with a contract alert's history row" do
      let(:customer) { create(:customer, external_id: "acme", currency: "USD") }
      let(:contract) { create(:contract, customer:, external_id: "ctr_123") }
      let(:product) { create(:product, organization: customer.organization, code: "llm_tokens") }
      let(:alert) { create(:contract_usage_amount_alert, organization: customer.organization, contract_external_id: "ctr_123", product:, code: "tokens_spend", name: "Tokens spend") }
      let(:triggered_alert) do
        create(:contract_triggered_alert, alert:, contract:, current_value: 1_500, previous_value: 1_000, crossed_thresholds: [{code: "warn", value: BigDecimal(1_200), recurring: false}], triggered_at: Time.zone.parse("2026-11-22 12:00:00"))
      end

      it "sends its v2 body under the same event" do
        webhook_service.call

        expect(Webhook.order(created_at: :desc).first.payload).to eq(
          "webhook_type" => "alert.triggered",
          "object_type" => "triggered_alert",
          "organization_id" => customer.organization_id,
          "triggered_alert" => {
            "lago_id" => triggered_alert.id,
            "lago_alert_id" => alert.id,
            "alert_code" => "tokens_spend",
            "alert_name" => "Tokens spend",
            "alert_type" => "usage_amount",
            "currency" => "USD",
            "lago_contract_id" => contract.id,
            "external_contract_id" => "ctr_123",
            "external_customer_id" => "acme",
            "current_value" => "1500.0",
            "previous_value" => "1000.0",
            "scope" => [{"type" => "contract", "product_code" => "llm_tokens", "with_product_filters" => false}],
            "crossed_thresholds" => [{"code" => "warn", "value" => "1200.0", "recurring" => false}],
            "triggered_at" => "2026-11-22T12:00:00Z"
          }
        )
      end
    end

    context "when SIDEKIQ_WEBHOOK is true" do
      before { ENV["SIDEKIQ_WEBHOOK"] = "true" }
      after { ENV.delete("SIDEKIQ_WEBHOOK") }

      it "enqueues the http job on the high priority queue" do
        webhook_service.call

        expect(SendHttpWebhookJob).to have_been_enqueued.on_queue("webhook_worker_high_priority")
      end
    end
  end
end
