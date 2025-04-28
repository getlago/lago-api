# frozen_string_literal: true

require "rails_helper"

RSpec.describe ::V1::UsageMonitoring::TriggeredAlertSerializer do
  subject(:serializer) { described_class.new(triggered_alert, root_name: "triggered_alert") }

  let(:triggered_alert) { create(:triggered_alert, crossed_thresholds: [{code: :warn, value: BigDecimal(2000)}], triggered_at: DateTime.new(2000, 1, 1, 12, 0, 0)) }

  before { triggered_alert }

  it "serializes the object" do
    result = JSON.parse(serializer.to_json)

    payload = result["triggered_alert"]
    expect(payload["lago_id"]).to eq(triggered_alert.id)
    expect(payload["lago_alert_id"]).to eq(triggered_alert.alert.id)
    expect(payload["lago_subscription_id"]).to eq(triggered_alert.subscription.id)
    expect(payload["alert_type"]).to eq("usage_amount")
    expect(payload["current_value"]).to eq("3000.0")
    expect(payload["previous_value"]).to eq("1000.0")
    expect(payload["crossed_thresholds"]).to eq([{"code" => "warn", "value" => "2000.0"}])
    expect(payload["triggered_at"]).to eq("2000-01-01T12:00:00Z")
  end
end
