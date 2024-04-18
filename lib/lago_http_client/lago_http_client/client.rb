# frozen_string_literal: true

require 'net/http/post/multipart'

module LagoHttpClient
  class Client
    RESPONSE_SUCCESS_CODES = [200, 201, 202, 204].freeze

    def initialize(url)
      @uri = URI(url)
      @http_client = Net::HTTP.new(uri.host, uri.port)
      @http_client.use_ssl = true if uri.scheme == 'https'
    end

    def post(body, headers)
      req = Net::HTTP::Post.new(uri.request_uri, 'Content-Type' => 'application/json')

      headers.each do |header|
        key = header.keys.first
        value = header[key]
        req[key] = value
      end

      req.body = body.to_json

      response = http_client.request(req)

      raise_error(response) unless RESPONSE_SUCCESS_CODES.include?(response.code.to_i)

      JSON.parse(response.body&.presence || '{}')
    rescue JSON::ParserError
      response.body&.presence || '{}'
    end

    def post_with_response(body, headers)
      req = Net::HTTP::Post.new(uri.request_uri, 'Content-Type' => 'application/json')

      headers.keys.each do |key|
        req[key] = headers[key]
      end

      req.body = body.to_json
      response = http_client.request(req)

      raise_error(response) unless RESPONSE_SUCCESS_CODES.include?(response.code.to_i)

      response
    end

    def post_multipart_file(file_content, file_type, file_name, options = {})
      params = options.merge(
        {
          'file1' => UploadIO.new(
            StringIO.new(file_content),
            file_type,
            file_name,
          ),
        },
      )

      req = Net::HTTP::Post::Multipart.new(
        uri.path,
        params,
      )

      response = http_client.request(req)

      raise_error(response) unless RESPONSE_SUCCESS_CODES.include?(response.code.to_i)

      response
    end

    def get(headers: {}, params: nil)
      path = params ? "#{uri.path}?#{URI.encode_www_form(params)}" : uri.path
      req = Net::HTTP::Get.new(path)

      headers.keys.each do |key|
        req[key] = headers[key]
      end

      response = http_client.request(req)

      raise_error(response) unless RESPONSE_SUCCESS_CODES.include?(response.code.to_i)

      JSON.parse(response.body&.presence || '{}')
    end

    private

    attr_reader :uri, :http_client

    def raise_error(response)
      raise(::LagoHttpClient::HttpError.new(response.code, response.body, uri))
    end
  end
end
