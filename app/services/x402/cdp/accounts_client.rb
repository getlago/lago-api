# frozen_string_literal: true

module X402
  module Cdp
    class AccountsClient
      HOST = "api.cdp.coinbase.com"
      PATHS = {evm: "/platform/v2/evm/accounts", svm: "/platform/v2/solana/accounts"}.freeze
      OPEN_TIMEOUT = 5
      READ_TIMEOUT = 5

      Lookup = Data.define(:family, :outcome, :http_status, :error_type, :correlation_id)

      def initialize(api_key_id:, api_key_secret:)
        @api_key_id = api_key_id
        @api_key_secret = api_key_secret
      end

      def lookup(family:, address:)
        path = "#{PATHS.fetch(family)}/#{address}"
        token = Jwt.generate(api_key_id:, api_key_secret:, request_method: "GET", request_host: HOST, request_path: path)

        request(family, path, {"Authorization" => "Bearer #{token}"})
      end

      private

      attr_reader :api_key_id, :api_key_secret

      def request(family, path, headers)
        LagoHttpClient::Client.new("https://#{HOST}#{path}", open_timeout: OPEN_TIMEOUT, read_timeout: READ_TIMEOUT).get(headers:)
        Lookup.new(family:, outcome: :found, http_status: 200, error_type: nil, correlation_id: nil)
      rescue LagoHttpClient::HttpError => e
        refused(family, e.error_code.to_i, e.error_body)
      rescue JSON::ParserError
        unavailable(family, reason: "malformed_response", status: 200)
      rescue => e
        unavailable(family, reason: "no_response", error: e.class.name)
      end

      def refused(family, status, raw)
        body = parse(raw)
        outcome = refusal_outcome(status, body["errorType"])
        log_failure(family:, reason: outcome, status:, error_type: body["errorType"], correlation_id: body["correlationId"])

        Lookup.new(family:, outcome:, http_status: status, error_type: body["errorType"], correlation_id: body["correlationId"])
      end

      def refusal_outcome(status, error_type)
        case status
        when 401, 403 then :forbidden
        when 429 then :rate_limited
        when 404 then (error_type == "not_found") ? :not_found : :unavailable
        when 400 then (error_type == "invalid_request") ? :invalid : :unavailable
        else :unavailable
        end
      end

      def unavailable(family, reason:, status: nil, error: nil)
        log_failure(family:, reason:, status:, error:)
        Lookup.new(family:, outcome: :unavailable, http_status: status, error_type: nil, correlation_id: nil)
      end

      def parse(raw)
        parsed = JSON.parse(raw.to_s)
        parsed.is_a?(Hash) ? parsed : {}
      rescue JSON::ParserError
        {}
      end

      def log_failure(**details)
        Rails.logger.warn("#{self.class.name} lookup failed #{details.compact.map { |key, value| "#{key}=#{value}" }.join(" ")}")
      end
    end
  end
end
