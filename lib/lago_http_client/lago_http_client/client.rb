# frozen_string_literal: true

module LagoHttpClient
  class Client
    RESPONSE_SUCCESS_CODES = [200, 201, 202, 204].freeze

    def initialize(url)
      @uri = URI(url)
      @http_client = Net::HTTP.new(uri.host, uri.port)
    end

    def post(body, headers)
      req = Net::HTTP::Post.new(uri.path, 'Content-Type' => 'application/json')

      headers.each do |header|
        key = header.keys.first
        value = header[key]
        req[key] = value
      end

      req.body = body.to_json

      response = http_client.request(req)

      raise_error(response) unless RESPONSE_SUCCESS_CODES.include?(response.code.to_i)

      JSON.parse(response.body)
    end

    private

    attr_reader :uri, :http_client

    def raise_error(response)
      raise ::LagoHttpClient::HttpError.new(response.code, response.body, uri)
    end
  end
end
