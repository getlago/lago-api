# frozen_string_literal: true

require "rails_helper"

RSpec.describe V2::SecurityLogSerializer, clickhouse: true do
  subject(:serializer) { described_class.new(security_log, root_name: "security_log") }

  let(:security_log) { create(:clickhouse_security_log) }

  it "serializes the object" do
    result = JSON.parse(serializer.to_json)

    expect(result["security_log"]["log_id"]).to eq(security_log.log_id)
    expect(result["security_log"]["log_type"]).to eq(security_log.log_type)
    expect(result["security_log"]["log_event"]).to eq(security_log.log_event)
    expect(result["security_log"]["user_email"]).to eq(security_log.user.email)
    expect(result["security_log"]["logged_at"]).to eq(security_log.logged_at.iso8601)
    expect(result["security_log"]["created_at"]).to eq(security_log.created_at.iso8601)
    expect(result["security_log"]["resources"]).to eq(security_log.resources)
    expect(result["security_log"]["device_info"]).to eq(security_log.device_info)
  end

  context "when the map holds a JSON-encoded value and a raw value" do
    let(:security_log) do
      create(
        :clickhouse_security_log,
        resources: {"payload" => {"id" => 1}.to_json, "email" => "test@example.com"},
        device_info: {"headers" => %w[a b].to_json, "os" => "macOS"}
      )
    end

    it "returns the JSON-encoded value parsed and the raw value unchanged" do
      result = JSON.parse(serializer.to_json)

      expect(result["security_log"]["resources"]).to eq(security_log.resources)
      expect(result["security_log"]["resources"]).to eq("payload" => {"id" => 1}, "email" => "test@example.com")
      expect(result["security_log"]["device_info"]).to eq(security_log.device_info)
      expect(result["security_log"]["device_info"]).to eq("headers" => %w[a b], "os" => "macOS")
    end
  end
end
