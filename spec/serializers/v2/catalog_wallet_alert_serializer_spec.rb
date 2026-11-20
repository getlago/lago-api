# frozen_string_literal: true

require "rails_helper"

describe V2::CatalogWalletAlertSerializer do
  subject(:payload) { described_class.new(alert).serialize }

  let_it_be(:organization) { create(:organization) }
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
      external_contract_id: nil,
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
