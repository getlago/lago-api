# frozen_string_literal: true

require "rails_helper"

RSpec.describe ::V1::UsageMonitoring::ResolvedAlertSerializer do
  subject(:serializer) { described_class.new(resolved_alert, root_name: "resolved_alert") }

  let(:resolved_alert) do
    create(:triggered_alert, alert:, subscription:, kind: :resolved, resolution_reason: :recovered,
      crossed_thresholds: [{code: "warn", value: BigDecimal(2000), recurring: false}],
      in_alarm_thresholds: ["low"], fully_resolved: false,
      triggered_at: DateTime.new(2000, 1, 1, 12, 0, 0))
  end
  let(:subscription) { create(:subscription, external_id: "ext-id", customer: create(:customer, external_id: "cust-ext-id")) }
  let(:alert) { create(:usage_current_amount_alert, subscription_external_id: "ext-id", code: "first", name: "First") }

  it "serializes the resolution with its own fields" do
    expect(JSON.parse(serializer.to_json)["resolved_alert"]).to eq(
      "lago_id" => resolved_alert.id,
      "lago_organization_id" => resolved_alert.organization_id,
      "lago_alert_id" => alert.id,
      "lago_subscription_id" => subscription.id,
      "external_subscription_id" => "ext-id",
      "lago_wallet_id" => nil,
      "external_customer_id" => "cust-ext-id",
      "billable_metric_code" => nil,
      "alert_name" => "First",
      "alert_code" => "first",
      "alert_type" => "current_usage_amount",
      "current_value" => "3000.0",
      "previous_value" => "1000.0",
      "recovered_thresholds" => [{"code" => "warn", "value" => "2000.0", "recurring" => false}],
      "in_alarm_thresholds" => ["low"],
      "fully_resolved" => false,
      "reason" => "recovered",
      "resolved_at" => "2000-01-01T12:00:00Z"
    )
  end

  context "when a wallet alert is closed by an edit" do
    let(:wallet) { create(:wallet, customer: create(:customer, external_id: "wallet-cust")) }
    let(:alert) { create(:wallet_balance_amount_alert, wallet:, organization: wallet.organization, code: "low") }
    let(:resolved_alert) do
      create(:triggered_alert, alert:, organization: wallet.organization, subscription: nil, wallet:,
        kind: :resolved, resolution_reason: :threshold_removed, in_alarm_thresholds: [], fully_resolved: true)
    end

    it "names the wallet, the customer and the reason" do
      payload = JSON.parse(serializer.to_json)["resolved_alert"]

      expect(payload.slice("lago_subscription_id", "lago_wallet_id", "external_customer_id", "reason", "fully_resolved"))
        .to eq("lago_subscription_id" => nil, "lago_wallet_id" => wallet.id, "external_customer_id" => "wallet-cust",
          "reason" => "threshold_removed", "fully_resolved" => true)
    end
  end
end
