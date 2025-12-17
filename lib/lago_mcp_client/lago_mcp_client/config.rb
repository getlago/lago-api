# frozen_string_literal: true

module LagoMcpClient
  class Config
    attr_accessor :mcp_server_url, :lago_api_key, :member_permissions, :timeout, :headers

    def initialize(mcp_server_url:, lago_api_key:, member_permissions: nil, timeout: 30, headers: {})
      @mcp_server_url = mcp_server_url
      @lago_api_key = lago_api_key
      @member_permissions = member_permissions
      @timeout = timeout
      @headers = headers
    end

    def lago_api_url
      @lago_api_url ||= URI.join(ENV["LAGO_API_URL"], "/api/v1").to_s
    end
  end
end
