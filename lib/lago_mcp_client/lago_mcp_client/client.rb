# frozen_string_literal: true

module LagoMcpClient
  class Client
    PROTOCOL_VERSION = "2024-11-05"
    CLIENT_NAME = "lago-mcp-client"
    CLIENT_VERSION = "0.1"

    attr_reader :config, :session_id, :sse_client, :http_client

    def initialize(config)
      @config = config
      @session_id = nil
      @sse_client = nil
      @http_client = LagoHttpClient::Client.new(config.server_url, read_timeout: config.timeout)
    end

    def setup!
      init_connection
      start_sse_client
    end

    def list_tools
      response = make_request(method: "tools/list")
      tools = response.dig(:body, "result", "tools") || []
      tools.map do |tool|
        Tool.new(
          name: tool["name"],
          description: tool["description"],
          input_schema: tool["inputSchema"]
        )
      end
    end

    def call_tool(name, arguments = {})
      response = make_request(
        method: "tools/call",
        params: { name:, arguments: }
      )
      response[:body]["result"]
    end

    def close_session
      @sse_client&.stop
      make_request(method: "close")
    end

    private

    def make_request(method:, params: {}, id: nil)
      headers = build_headers

      body = {
        jsonrpc: "2.0",
        method: method,
        params: params,
        id: id || SecureRandom.uuid
      }

      response = http_client.post_with_response(body, headers)
      parsed_body = parse_sse_body(response.body)
      sse_id = extract_sse_id(response.body)

      {
        status: response.code.to_i,
        headers: response.each_header.to_h,
        body: parsed_body,
        sse_id: sse_id
      }
    rescue StandardError => e
      { error: e.message }
    end

    def build_headers
      {
        "Content-Type" => "application/json",
        "Accept" => "application/json,text/event-stream",
        "Mcp-Session-Id" => session_id,
        "X-LAGO-API-KEY" => config.lago_api_key,
        "X-LAGO-API-URL" => config.lago_api_url
      }.compact.merge(config.headers)
    end

    def start_sse_client
      @sse_client = SseClient.new(url: config.server_url, session_id:)
      @sse_client.start
    end

    def init_connection
      response = make_request(
        method: "initialize",
        params: {
          protocolVersion: PROTOCOL_VERSION,
          capabilities: {},
          clientInfo: { name: CLIENT_NAME, version: CLIENT_VERSION }
        }
      )

      @session_id ||= response[:headers]["mcp-session-id"]
      make_request(method: "notifications/initialized")
    end

    def parse_sse_body(body)
      return nil unless body

      body.split("\n").each do |line|
        return JSON.parse(line[6..-1]) if line.start_with?("data: ")
      end
      nil
    rescue JSON::ParserError
      nil
    end

    def extract_sse_id(body)
      return nil unless body

      body.split("\n").find { |line| line.start_with?("id: ") }&.delete_prefix("id: ")
    end
  end
end
