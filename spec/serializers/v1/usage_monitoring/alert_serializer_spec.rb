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
    expect(payload["billable_metric_code"]).to be_nil
    expect(payload["name"]).to eq("General Alert")
    expect(payload["code"]).to eq("yolo")
    expect(payload["alert_type"]).to eq("usage_amount")
    expect(payload["thresholds"]).to eq([
      {"code" => "warn10", "value" => "10.0", "recurring" => false},
      {"code" => "warn12", "value" => "12.0", "recurring" => false},
      {"code" => "rec", "value" => "33.0", "recurring" => true}
    ])
    expect(payload["previous_value"]).to eq("800.0")
    expect(payload["last_processed_at"]).to eq("2000-01-01T12:00:00Z")
  end

  context "with billable_metric_usage_amount alert" do
    let(:alert) { create(:billable_metric_usage_amount_alert) }

    it "has the billable_metric_id the object" do
      payload = result["alert"]
      expect(payload["billable_metric_code"]).to eq alert.billable_metric.code
    end
  end

  context "with soft deleted alert" do
    before { alert.discard }

    it "includes deleted_at field" do
      payload = result["alert"]
      expect(payload["deleted_at"]).to eq(alert.deleted_at.iso8601)
    end
  end
end
