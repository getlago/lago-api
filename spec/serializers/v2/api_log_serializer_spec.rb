# frozen_string_literal: true

require "rails_helper"

RSpec.describe V2::ApiLogSerializer, clickhouse: true do
  subject(:serializer) { described_class.new(api_log, root_name: "api_log") }

  let(:api_log) do
    create(
      :clickhouse_api_log,
      request_body: {"metadata" => "{\"foo\":\"bar\"}", "plain" => "hello"},
      request_response: {"items" => "[1,2,3]", "note" => "not-json"}
    )
  end

  let(:result) { JSON.parse(serializer.to_json)["api_log"] }

  it "serializes the object" do
    expect(result["request_id"]).to eq(api_log.request_id)
    expect(result["client"]).to eq(api_log.client)
    expect(result["http_method"]).to eq(api_log.http_method)
    expect(result["http_status"]).to eq(api_log.http_status)
    expect(result["request_origin"]).to eq(api_log.request_origin)
    expect(result["request_path"]).to eq(api_log.request_path)
    expect(result["api_version"]).to eq(api_log.api_version)
    expect(result["logged_at"]).to eq(api_log.logged_at.iso8601)
    expect(result["created_at"]).to eq(api_log.created_at.iso8601)
  end

  it "parses JSON-encoded request_body values one level deep" do
    expect(result["request_body"]).to eq("metadata" => {"foo" => "bar"}, "plain" => "hello")
  end

  it "parses JSON-encoded request_response values one level deep" do
    expect(result["request_response"]).to eq("items" => [1, 2, 3], "note" => "not-json")
  end

  context "when a value is not valid JSON" do
    let(:api_log) do
      create(
        :clickhouse_api_log,
        request_body: {"raw" => "not json at all"},
        request_response: {"raw" => "still not json"}
      )
    end

    it "returns the value unchanged" do
      expect(result["request_body"]).to eq("raw" => "not json at all")
      expect(result["request_response"]).to eq("raw" => "still not json")
    end
  end
end
