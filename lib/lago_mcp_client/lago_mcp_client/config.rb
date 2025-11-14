# frozen_string_literal: true

module LagoMcpClient
  class Config
    attr_accessor :server_url, :lago_api_key, :timeout, :headers

    def initialize(server_url:, lago_api_key:, timeout: 30, headers: {})
      @server_url = server_url
      @lago_api_key = lago_api_key
      @timeout = timeout
      @headers = headers
    end

    def lago_api_url
      @lago_api_url ||= URI.join(
        ENV.fetch("LAGO_API_URL", "https://api.lago.dev"),
        "/api/v1"
      ).to_s
    end
  end
end
