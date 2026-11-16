# frozen_string_literal: true

require "rails_helper"

RSpec.describe Clickhouse::SecurityLog, clickhouse: true do
  subject(:security_log) { create(:clickhouse_security_log) }

  let_it_be(:organization) { create_default(:organization) }

  describe "associations" do
    it do
      expect(security_log).to belong_to(:organization)
      expect(security_log).to belong_to(:user).optional
      expect(security_log).to belong_to(:api_key).optional
    end
  end

  describe "#ensure_log_id" do
    it "sets the log_id if it is not set" do
      expect(security_log.log_id).to be_present
    end
  end

  describe "#resources" do
    subject(:security_log) do
      create(:clickhouse_security_log, resources: {
        "email" => "test@example.com",
        "roles" => '["admin", "finance"]',
        "name" => '{"deleted":"A","added":"B"}'
      })
    end

    it "deserializes nested JSON string values" do
      log = described_class.find_by(log_id: security_log.log_id)

      expect(log.resources).to eq({
        "email" => "test@example.com",
        "roles" => %w[admin finance],
        "name" => {"deleted" => "A", "added" => "B"}
      })
    end

    context "when a value is NULL" do
      subject(:security_log) do
        create(:clickhouse_security_log, log_event: "api_key.rotated", resources: {
          "name" => nil,
          "value_ending" => '{"deleted":"A","added":"B"}'
        })
      end

      it "returns nil for that value and parses the others" do
        log = described_class.find_by(log_id: security_log.log_id)

        expect(log.resources).to eq({
          "name" => nil,
          "value_ending" => {"deleted" => "A", "added" => "B"}
        })
      end
    end

    context "when a value is an empty string" do
      subject(:security_log) do
        create(:clickhouse_security_log, resources: {"name" => "", "email" => "test@example.com"})
      end

      it "keeps the empty string" do
        log = described_class.find_by(log_id: security_log.log_id)

        expect(log.resources).to eq({"name" => "", "email" => "test@example.com"})
      end
    end
  end

  describe "#device_info" do
    subject(:security_log) do
      create(:clickhouse_security_log, device_info: {
        "browser" => "Chrome",
        "resolution" => '{"width":1920,"height":1080}'
      })
    end

    it "deserializes nested JSON string values" do
      log = described_class.find_by(log_id: security_log.log_id)

      expect(log.device_info).to eq({
        "browser" => "Chrome",
        "resolution" => {"width" => 1920, "height" => 1080}
      })
    end

    context "when a value is NULL" do
      subject(:security_log) do
        create(:clickhouse_security_log, device_info: {
          "os" => nil,
          "browser" => "Chrome",
          "resolution" => '{"width":1920,"height":1080}'
        })
      end

      it "returns nil for that value and parses the others" do
        log = described_class.find_by(log_id: security_log.log_id)

        expect(log.device_info).to eq({
          "os" => nil,
          "browser" => "Chrome",
          "resolution" => {"width" => 1920, "height" => 1080}
        })
      end
    end
  end
end
