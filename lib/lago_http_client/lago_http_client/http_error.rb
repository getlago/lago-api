# frozen_string_literal: true

module LagoHttpClient
  class HttpError < StandardError
    attr_reader :error_code, :error_body, :uri

    def initialize(code, body, uri)
      @error_code = code
      @error_body = body
      @uri = uri
    end

    def message
      "HTTP #{error_code} - URI: #{uri}.\nError: #{error_body}"
    end

    def json_message
      JSON.parse(error_body)
    end
  end
end
