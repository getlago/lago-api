# frozen_string_literal: true

require "rails_helper"

RSpec.describe ::V1::UsageMonitoring::AlertSerializer do
  subject(:serializer) { described_class.new(alert, root_name: "alert") }

  let(:alert) { create(:alert, :processed, subscription_external_id: "ext-id", recurring_threshold: 33, thresholds: [10, 12], code: :yolo) }
  let(:result) { JSON.parse(serializer.to_json) }

  before { alert }

  it "serializes the object" do
    payload = result["alert"]
    expect(payload["lago_id"]).to eq(alert.id)
    expect(payload["subscription_external_id"]).to eq("ext-id")
    expect(payload["name"]).to eq("General Alert")
    expect(payload["code"]).to eq("yolo")
    expect(payload["alert_type"]).to eq("current_usage_amount")
    expect(payload["thresholds"]).to eq([
      {"code" => "warn10", "value" => "10.0", "recurring" => false},
      {"code" => "warn12", "value" => "12.0", "recurring" => false},
      {"code" => "rec", "value" => "33.0", "recurring" => true}
    ])
    expect(payload["previous_value"]).to eq("800.0")
    expect(payload["last_processed_at"]).to eq("2000-01-01T12:00:00Z")
    expect(payload["billable_metric"]).to be_nil
  end

  context "with billable_metric_current_usage_amount alert" do
    let(:alert) { create(:billable_metric_current_usage_amount_alert) }

    it "has the billable_metric_id the object" do
      payload = result["alert"]["billable_metric"]
      expect(payload["lago_id"]).to eq alert.billable_metric.id
      expect(payload["code"]).to eq alert.billable_metric.code
      expect(payload["field_name"]).to be_nil
    end
  end
end
