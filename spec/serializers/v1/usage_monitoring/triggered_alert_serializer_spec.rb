# frozen_string_literal: true

require "rails_helper"

RSpec.describe ::V1::UsageMonitoring::TriggeredAlertSerializer do
  subject(:serializer) { described_class.new(triggered_alert, root_name: "triggered_alert") }

  let(:triggered_alert) { create(:triggered_alert, alert:, subscription:, triggered_at: DateTime.new(2000, 1, 1, 12, 0, 0)) }
  let(:subscription) { create(:subscription, external_id: "ext-id") }

  before { triggered_alert }

  context "with usage_amount alert" do
    let(:alert) { create(:usage_amount_alert, subscription_external_id: "ext-id", code: "first") }

    it "serializes the object" do
      result = JSON.parse(serializer.to_json)

      payload = result["triggered_alert"]
      expect(payload["lago_id"]).to eq(triggered_alert.id)
      expect(payload["lago_alert_id"]).to eq(triggered_alert.alert.id)
      expect(payload["lago_subscription_id"]).to eq(triggered_alert.subscription.id)
      expect(payload["lago_billable_metric_id"]).to be_nil
      expect(payload["alert_name"]).to eq("General Alert")
      expect(payload["alert_code"]).to eq("first")
      expect(payload["alert_type"]).to eq("usage_amount")
      expect(payload["current_value"]).to eq("3000.0")
      expect(payload["previous_value"]).to eq("1000.0")
      expect(payload["crossed_thresholds"]).to eq([
        {"code" => "warn", "value" => "2000.0", "recurring" => false},
        {"code" => "repeat", "value" => "2500.0", "recurring" => true}
      ])
      expect(payload["triggered_at"]).to eq("2000-01-01T12:00:00Z")
    end
  end

  context "with billable_metric_usage_amount alert" do
    let(:alert) { create(:billable_metric_usage_amount_alert, subscription_external_id: "ext-id") }

    it "has the billable_metric_id the object" do
      result = JSON.parse(serializer.to_json)

      payload = result["triggered_alert"]
      expect(payload["lago_billable_metric_id"]).to eq alert.billable_metric_id
    end
  end
end
