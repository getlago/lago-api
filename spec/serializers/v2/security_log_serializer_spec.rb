# frozen_string_literal: true

require "rails_helper"

RSpec.describe V2::SecurityLogSerializer, clickhouse: true do
  subject(:serializer) { described_class.new(security_log, root_name: "security_log") }

  let(:user) { create(:user, email: "user@example.test") }
  let(:membership) { create(:membership, user:) }
  let(:security_log) do
    create(
      :clickhouse_security_log,
      membership:,
      log_id: "security-log-1",
      log_type: "user",
      log_event: "user.signed_up",
      resources:,
      device_info:
    )
  end

  let(:result) { JSON.parse(serializer.to_json)["security_log"] }

  # Constant fields with the two maps passed in; the timestamps are read from the record since they
  # are assigned at creation. The serializer renders them at whole seconds by default. resources and
  # device_info are parsed one level deep by Clickhouse::SecurityLog before the serializer reads them.
  def expected_payload(resources:, device_info:)
    {
      "log_id" => "security-log-1",
      "log_type" => "user",
      "log_event" => "user.signed_up",
      "user_email" => "user@example.test",
      "logged_at" => security_log.logged_at.iso8601,
      "created_at" => security_log.created_at.iso8601,
      "resources" => resources,
      "device_info" => device_info
    }
  end

  context "when the maps hold raw values" do
    let(:resources) { {"user_email" => "test@example.com"} }
    let(:device_info) { {"browser" => "Chrome", "os" => "macOS"} }

    it "serializes the object" do
      expect(result).to eq(
        expected_payload(
          resources: {"user_email" => "test@example.com"},
          device_info: {"browser" => "Chrome", "os" => "macOS"}
        )
      )
    end
  end

  context "when a map holds a JSON-encoded value and a raw value" do
    let(:resources) { {"payload" => {"id" => 1}.to_json, "email" => "test@example.com"} }
    let(:device_info) { {"headers" => %w[a b].to_json, "os" => "macOS"} }

    it "returns the JSON-encoded value parsed and the raw value unchanged" do
      expect(result).to eq(
        expected_payload(
          resources: {"payload" => {"id" => 1}, "email" => "test@example.com"},
          device_info: {"headers" => %w[a b], "os" => "macOS"}
        )
      )
    end
  end
end
