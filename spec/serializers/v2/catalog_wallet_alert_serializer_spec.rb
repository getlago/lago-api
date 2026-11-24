# frozen_string_literal: true

require "rails_helper"

describe V2::CatalogWalletAlertSerializer do
  subject(:payload) { described_class.new(alert).serialize }

  let_it_be(:organization) { create(:organization) }

  context "with a plan wallet's template" do
    let_it_be(:catalog_plan) { create(:catalog_plan, organization:, code: "pro", currency: "EUR") }
    let_it_be(:plan_wallet) { create(:plan_wallet, organization:, catalog_plan:, code: "prepaid", currency: "EUR") }

    let(:alert) { create(:plan_wallet_alert, organization:, plan_wallet:, alert_type: "ongoing_balance", code: "low_ongoing", name: "Low ongoing balance") }

    before do
      [
        {code: "low", value: 10_000, notify_on: %w[triggered resolved]},
        {code: "overdrawn", value: -5_000},
        {code: "every_50", value: 5_000, recurring: true}
      ].each do |threshold|
        create(:catalog_wallet_alert_threshold, :template, organization:, plan_wallet_alert: alert, **threshold)
      end
    end

    it "serializes the template, its thresholds by value with the recurring one last" do
      expect(payload).to eq(
        lago_id: alert.id,
        lago_wallet_id: plan_wallet.id,
        wallet_code: "prepaid",
        currency: "EUR",
        plan_code: "pro",
        lago_contract_id: nil,
        external_contract_id: nil,
        contract_code: nil,
        external_customer_id: nil,
        code: "low_ongoing",
        name: "Low ongoing balance",
        alert_type: "ongoing_balance",
        direction: "decreasing",
        thresholds: [
          {code: "overdrawn", value: BigDecimal("-5000"), recurring: false, notify_on: %w[triggered]},
          {code: "low", value: BigDecimal("10000"), recurring: false, notify_on: %w[triggered resolved]},
          {code: "every_50", value: BigDecimal("5000"), recurring: true, notify_on: %w[triggered]}
        ],
        previous_value: nil,
        last_processed_at: nil,
        created_at: alert.created_at.iso8601,
        updated_at: alert.updated_at.iso8601
      )
    end
  end

  context "with a contract wallet's alert" do
    let_it_be(:customer) { create(:customer, organization:, external_id: "cus_42", currency: "EUR") }
    let_it_be(:contract) { create(:contract, customer:, external_id: "ctr_42") }
    let_it_be(:catalog_wallet) { create(:catalog_wallet, organization:, customer:, contract:, code: "prepaid") }

    let(:alert) do
      create(:catalog_wallet_alert, organization:, catalog_wallet:, alert_type: "balance", code: "low_balance", name: "Low balance", previous_value: 1_500, last_processed_at: Time.zone.parse("2026-11-24T10:00:00Z"))
    end

    before { create(:catalog_wallet_alert_threshold, organization:, catalog_wallet_alert: alert, code: "low", value: 2_000, notify_on: %w[triggered resolved]) }

    it "serializes the alert with its contract, its customer and its evaluation state, and no plan" do
      expect(payload).to eq(
        lago_id: alert.id,
        lago_wallet_id: catalog_wallet.id,
        wallet_code: "prepaid",
        currency: "EUR",
        plan_code: nil,
        lago_contract_id: contract.id,
        external_contract_id: "ctr_42",
        contract_code: contract.code,
        external_customer_id: "cus_42",
        code: "low_balance",
        name: "Low balance",
        alert_type: "balance",
        direction: "decreasing",
        thresholds: [{code: "low", value: BigDecimal("2000"), recurring: false, notify_on: %w[triggered resolved]}],
        previous_value: BigDecimal("1500"),
        last_processed_at: "2026-11-24T10:00:00Z",
        created_at: alert.created_at.iso8601,
        updated_at: alert.updated_at.iso8601
      )
    end
  end
end
