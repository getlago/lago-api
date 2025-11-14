# frozen_string_literal: true

require "rails_helper"

RSpec.describe LagoMcpClient::Client do
  let(:config) do
    double(
      "Config",
      server_url: "https://mcp.example.com",
      timeout: 5,
      lago_api_key: "secret",
      lago_api_url: "https://api.lago.dev",
      headers: { "X-Custom" => "foo" }
    )
  end

  let(:http_client) { instance_double(LagoHttpClient::Client) }
  let(:sse_client) { instance_double(LagoMcpClient::SseClient, start: true, stop: true) }

  subject(:client) { described_class.new(config) }

  before do
    allow(LagoHttpClient::Client).to receive(:new).and_return(http_client)
    allow(LagoMcpClient::SseClient).to receive(:new).and_return(sse_client)
  end

  describe "#initialize" do
    it "initializes with proper config and builds http client" do
      expect(client.instance_variable_get(:@http_client)).to eq(http_client)
    end
  end

  describe "#setup!" do
    before do
      allow(client).to receive(:init_connection)
    end

    it "initializes connection and starts SSE client" do
      expect(client).to receive(:init_connection)
      expect(LagoMcpClient::SseClient).to receive(:new)
      expect(sse_client).to receive(:start)

      client.setup!
    end
  end

  describe "#list_tools" do
    let(:response_body) do
      {
        "result" => {
          "tools" => [
            { "name" => "tool_a", "description" => "desc a", "inputSchema" => { "type" => "object" } },
            { "name" => "tool_b", "description" => "desc b", "inputSchema" => { "type" => "object" } }
          ]
        }
      }
    end

    before do
      allow(client).to receive(:make_request).with(method: "tools/list").and_return({ body: response_body })
      stub_const("LagoMcpClient::Tool", Struct.new(:name, :description, :input_schema))
    end

    it "returns an array of Tool instances" do
      tools = client.list_tools
      expect(tools.size).to eq(2)
      expect(tools.first.name).to eq("tool_a")
      expect(tools.last.description).to eq("desc b")
    end
  end

  describe "#call_tool" do
    before do
      allow(client).to receive(:make_request).and_return({ body: { "result" => { "status" => "ok" } } })
    end

    it "calls the tool with given name and arguments" do
      result = client.call_tool("echo", { message: "hello" })
      expect(result).to eq({ "status" => "ok" })
    end
  end

  describe "#close_session" do
    before do
      client.instance_variable_set(:@sse_client, sse_client)
      allow(client).to receive(:make_request)
    end

    it "stops the SSE client and sends close request" do
      expect(sse_client).to receive(:stop)
      expect(client).to receive(:make_request).with(method: "close")
      client.close_session
    end
  end

  describe "#make_request" do
    let(:mock_response) do
      instance_double(
        Net::HTTPResponse,
        code: "200",
        body: "id: 42\ndata: {\"result\": {\"ok\": true}}",
        each_header: { "mcp-session-id" => "abc123" }
      )
    end

    before do
      allow(http_client).to receive(:post_with_response).and_return(mock_response)
    end

    it "returns parsed JSON and SSE id" do
      result = client.send(:make_request, method: "tools/list")

      expect(result[:status]).to eq(200)
      expect(result[:body]).to eq({ "result" => { "ok" => true } })
      expect(result[:sse_id]).to eq("42")
      expect(result[:headers]["mcp-session-id"]).to eq("abc123")
    end

    it "returns error hash if request fails" do
      allow(http_client).to receive(:post_with_response).and_raise(StandardError.new("boom"))
      result = client.send(:make_request, method: "tools/list")
      expect(result).to eq({ error: "boom" })
    end
  end

  describe "#build_headers" do
    before do
      client.instance_variable_set(:@session_id, "sess-123")
    end

    it "builds headers correctly" do
      headers = client.send(:build_headers)
      expect(headers["Content-Type"]).to eq("application/json")
      expect(headers["Mcp-Session-Id"]).to eq("sess-123")
      expect(headers["X-LAGO-API-KEY"]).to eq("secret")
      expect(headers["X-LAGO-API-URL"]).to eq("https://api.lago.dev")
      expect(headers["X-Custom"]).to eq("foo")
    end
  end

  describe "#parse_sse_body" do
    it "returns parsed data when body contains data line" do
      body = "id: 123\ndata: {\"hello\": \"world\"}\n"
      result = client.send(:parse_sse_body, body)
      expect(result).to eq({ "hello" => "world" })
    end

    it "returns nil for invalid JSON" do
      body = "data: {invalid}\n"
      expect(client.send(:parse_sse_body, body)).to be_nil
    end

    it "returns nil when no data line" do
      expect(client.send(:parse_sse_body, "id: 10\n")).to be_nil
    end
  end

  describe "#extract_sse_id" do
    it "extracts the id line value" do
      body = "id: 123\ndata: {}\n"
      expect(client.send(:extract_sse_id, body)).to eq("123")
    end

    it "returns nil if no id line" do
      expect(client.send(:extract_sse_id, "data: {}\n")).to be_nil
    end
  end

  describe "#init_connection" do
    let(:init_response) do
      {
        headers: { "mcp-session-id" => "sess-abc" }
      }
    end

    before do
      allow(client).to receive(:make_request).and_return(init_response)
    end

    it "sets session id and sends notifications/initialized" do
      expect(client).to receive(:make_request).with(hash_including(method: "initialize")).ordered
      expect(client).to receive(:make_request).with(method: "notifications/initialized").ordered
      client.send(:init_connection)
      expect(client.instance_variable_get(:@session_id)).to eq("sess-abc")
    end
  end
end
