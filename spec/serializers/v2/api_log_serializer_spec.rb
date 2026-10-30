# frozen_string_literal: true

require "rails_helper"

RSpec.describe V2::ApiLogSerializer, clickhouse: true do
  subject(:serializer) { described_class.new(api_log, root_name: "api_log") }

  let(:api_log) do
    create(
      :clickhouse_api_log,
      request_id: "api-log-1",
      client: "RSpec",
      http_method: "post",
      http_status: 200,
      request_origin: "https://lago.test",
      request_path: "/api/v1/test-endpoint",
      api_version: "v1",
      request_body:,
      request_response:
    )
  end

  let(:result) { JSON.parse(serializer.to_json)["api_log"] }

  # Constant fields with the two JSON maps passed in; the timestamps are read from the record
  # since they are assigned at creation. The serializer renders them at whole seconds by default.
  def expected_payload(request_body:, request_response:)
    {
      "request_id" => "api-log-1",
      "client" => "RSpec",
      "http_method" => "post",
      "http_status" => 200,
      "request_origin" => "https://lago.test",
      "request_path" => "/api/v1/test-endpoint",
      "request_body" => request_body,
      "request_response" => request_response,
      "api_version" => "v1",
      "logged_at" => api_log.logged_at.iso8601,
      "created_at" => api_log.created_at.iso8601
    }
  end

  context "when the map values are JSON-encoded" do
    let(:request_body) { {"metadata" => "{\"foo\":\"bar\"}", "plain" => "hello"} }
    let(:request_response) { {"items" => "[1,2,3]", "note" => "not-json"} }

    it "serializes the object and parses the JSON values one level deep" do
      expect(result).to eq(
        expected_payload(
          request_body: {"metadata" => {"foo" => "bar"}, "plain" => "hello"},
          request_response: {"items" => [1, 2, 3], "note" => "not-json"}
        )
      )
    end
  end

  context "when a map value is not valid JSON" do
    let(:request_body) { {"raw" => "not json at all"} }
    let(:request_response) { {"raw" => "still not json"} }

    it "returns the value unchanged" do
      expect(result).to eq(
        expected_payload(
          request_body: {"raw" => "not json at all"},
          request_response: {"raw" => "still not json"}
        )
      )
    end
  end
end
