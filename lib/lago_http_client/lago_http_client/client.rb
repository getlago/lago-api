# frozen_string_literal: true

require "net/http/post/multipart"
require "event_stream_parser"

module LagoHttpClient
  class Client
    RESPONSE_SUCCESS_CODES = [200, 201, 202, 204].freeze
    MAX_RETRIES_ATTEMPTS = 3

    attr_reader :uri, :retries_on

    def initialize(url, read_timeout: nil, write_timeout: nil, retries_on: [])
      @uri = URI(url)
      @http_client = Net::HTTP.new(uri.host, uri.port)
      @http_client.read_timeout = read_timeout if read_timeout.present?
      @http_client.write_timeout = write_timeout if write_timeout.present?
      @http_client.use_ssl = true if uri.scheme == "https"
      @retries_on = retries_on
    end

    def post(body, headers)
      req = Net::HTTP::Post.new(uri.request_uri, "Content-Type" => "application/json")

      headers.each do |header|
        key = header.keys.first
        value = header[key]
        req[key] = value
      end

      req.body = body.to_json
      response = request(req)

      JSON.parse(response.body.presence || "{}")
    rescue JSON::ParserError
      response.body.presence || "{}"
    end

    def post_with_response(body, headers)
      req = Net::HTTP::Post.new(uri.request_uri, "Content-Type" => "application/json")

      headers.keys.each do |key|
        req[key] = headers[key]
      end

      req.body = body.to_json
      request(req)
    end

    def put_with_response(body, headers)
      req = Net::HTTP::Put.new(uri.request_uri, "Content-Type" => "application/json")

      headers.keys.each do |key|
        req[key] = headers[key]
      end

      req.body = body.to_json
      request(req)
    end

    def post_multipart_file(params = {})
      req = Net::HTTP::Post::Multipart.new(
        uri.path,
        params
      )

      request(req)
    end

    def post_url_encoded(params, headers)
      encoded_form = URI.encode_www_form(params)

      req = Net::HTTP::Post.new(uri.request_uri, "Content-Type" => "application/x-www-form-urlencoded")
      headers.keys.each do |key|
        req[key] = headers[key]
      end

      response = request(req, encoded_form)
      JSON.parse(response.body.presence || "{}")
    end

    def post_with_stream(body, headers = {}, &block)
      req = Net::HTTP::Post.new(uri.request_uri, {"Content-Type" => "application/json"}.merge(headers))
      req.body = body.to_json

      parser = EventStreamParser::Parser.new

      http_client.start do |http|
        http.request(req) do |response|
          raise_error(response) unless RESPONSE_SUCCESS_CODES.include?(response.code.to_i)

          response.read_body do |chunk|
            parser.feed(chunk) do |type, data, id, reconnection_time|
              yield(type, data, id, reconnection_time) if block_given?
            end
          end
        end
      end
    end

    def get(headers: {}, params: nil, body: nil)
      path = params ? "#{uri.path}?#{URI.encode_www_form(params)}" : uri.path
      req = Net::HTTP::Get.new(path)
      req.body = URI.encode_www_form(body) if body.present?

      headers.keys.each do |key|
        req[key] = headers[key]
      end

      response = request(req)
      JSON.parse(response.body.presence || "{}")
    end

    private

    attr_reader :http_client

    def raise_error(response)
      raise(
        ::LagoHttpClient::HttpError.new(response.code, response.body, uri, response_headers: response.each_header.to_h)
      )
    end

    def request(req, params = nil)
      attempt = 0

      response = begin
        attempt += 1
        http_client.request(req, params)
      rescue => e
        if retries_on.include?(e.class)
          retry if attempt < MAX_RETRIES_ATTEMPTS
        else
          raise
        end
      end

      raise_error(response) unless RESPONSE_SUCCESS_CODES.include?(response.code.to_i)
      response
    end
  end
end
