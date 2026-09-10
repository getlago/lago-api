# frozen_string_literal: true

require "rails_helper"

RSpec.describe ::V1::UsageMonitoring::ResolvedAlertSerializer do
  subject(:serializer) { described_class.new(resolved_alert, root_name: "triggered_alert") }

  let(:resolved_alert) do
    create(:triggered_alert, alert:, subscription:, kind: :resolved,
      in_alarm_thresholds: ["warn"], fully_resolved: false,
      triggered_at: DateTime.new(2000, 1, 1, 12, 0, 0))
  end
  let(:subscription) { create(:subscription, external_id: "ext-id", customer: create(:customer, external_id: "cust-ext-id")) }
  let(:alert) { create(:usage_current_amount_alert, subscription_external_id: "ext-id", code: "first") }

  before { resolved_alert }

  it "serializes the object" do
    result = JSON.parse(serializer.to_json)

    payload = result["triggered_alert"]
    expect(payload["lago_id"]).to eq(resolved_alert.id)
    expect(payload["lago_alert_id"]).to eq(alert.id)
    expect(payload["external_subscription_id"]).to eq("ext-id")
    expect(payload["external_customer_id"]).to eq("cust-ext-id")
    expect(payload["alert_code"]).to eq("first")
    expect(payload["current_value"]).to eq("3000.0")
    expect(payload["previous_value"]).to eq("1000.0")
    expect(payload["crossed_thresholds"]).to eq([
      {"code" => "warn", "value" => "2000.0", "recurring" => false},
      {"code" => "repeat", "value" => "2500.0", "recurring" => true}
    ])
  end

  it "adds the resolution fields" do
    result = JSON.parse(serializer.to_json)

    payload = result["triggered_alert"]
    expect(payload["in_alarm_thresholds"]).to eq(["warn"])
    expect(payload["fully_resolved"]).to be false
    expect(payload["resolved_at"]).to eq("2000-01-01T12:00:00Z")
  end

  context "when every watched line is back on the safe side" do
    let(:resolved_alert) do
      create(:triggered_alert, alert:, subscription:, kind: :resolved,
        in_alarm_thresholds: [], fully_resolved: true,
        triggered_at: DateTime.new(2000, 1, 1, 12, 0, 0))
    end

    it "reports the alert as fully resolved" do
      result = JSON.parse(serializer.to_json)

      payload = result["triggered_alert"]
      expect(payload["in_alarm_thresholds"]).to eq([])
      expect(payload["fully_resolved"]).to be true
    end
  end
end
