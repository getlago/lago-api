# frozen_string_literal: true

module X402
  module Facilitator
    class CoinbaseCdpAdapter
      HOST = "api.cdp.coinbase.com"
      BASE_PATH = "/platform/v2/x402"
      OPEN_TIMEOUT = 5
      READ_TIMEOUT = 10
      SETTLE_READ_TIMEOUT = 20

      TERMINAL_REASON = /\A(invalid_[a-z0-9_]+|insufficient_funds|unsupported_scheme)\z/
      AMBIGUOUS_REASON = /(nonce_already_used|nonce_used|already|transaction_failed|transaction_state|failed_onchain|simulation_failed)/

      Answer = Data.define(:status, :body, :parsed)
      class NoResponse < StandardError; end
      private_constant :Answer, :NoResponse

      def initialize(api_key_id:, api_key_secret:)
        @api_key_id = api_key_id
        @api_key_secret = api_key_secret
      end

      def verify(payment:, payment_requirements:)
        answer = request_or_unavailable("verify") { post("/verify", payment, payment_requirements, READ_TIMEOUT) }
        raise_for_access!("verify", answer)
        raise unavailable("verify", answer) if answer.status >= 500 || !answer.parsed

        body = answer.body
        reason = body["invalidReason"].presence || body["errorType"].presence || "verify_failed" unless body["isValid"] == true
        log_failure("verify", reason, status: answer.status, correlation_id: body["correlationId"]) if reason

        VerifyResult.new(valid: body["isValid"] == true, payer: body["payer"], invalid_reason: reason, response: body)
      end

      def settle(payment:, payment_requirements:)
        started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        result = settle_result(payment, payment_requirements)

        unless result.settled?
          duration = (Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_at).round(2)
          log_failure("settle", result.error_reason, outcome: result.outcome, network: result.network, correlation_id: result.response["correlationId"], duration:)
        end

        result
      end

      def supported
        answer = request_or_unavailable("supported") { get("/supported") }
        raise_for_access!("supported", answer)
        raise unavailable("supported", answer) if answer.status >= 500 || !answer.parsed

        SupportedResult.new(kinds: Array(answer.body["kinds"]), response: answer.body)
      end

      private

      attr_reader :api_key_id, :api_key_secret

      def settle_result(payment, payment_requirements)
        answer = begin
          post("/settle", payment, payment_requirements, SETTLE_READ_TIMEOUT)
        rescue NoResponse
          return settle_outcome(:no_response, error_reason: "no_response")
        end
        raise_for_access!("settle", answer)

        classify_settle(answer)
      end

      def classify_settle(answer)
        body = answer.body
        return settle_outcome(:server_error, error_reason: "malformed_response") unless answer.parsed
        return settle_outcome(:settlement_pending, transaction: body["transaction"], response: body, error_reason: "settlement_pending") if body["errorReason"] == "settlement_pending"
        return settle_outcome(:server_error, response: body, error_reason: "server_error") if answer.status >= 500

        if body["success"] == true
          return settle_outcome(:settled, transaction: body["transaction"], response: body) if body["transaction"].present?

          return settle_outcome(:server_error, response: body, error_reason: "malformed_response")
        end

        reason = body["errorReason"].presence || body["errorType"].presence || "unexpected_settle_error"
        settle_outcome(terminal?(reason, body) ? :failed : :unconfirmed_failure, response: body, error_reason: reason)
      end

      def terminal?(reason, body)
        TERMINAL_REASON.match?(reason) && !AMBIGUOUS_REASON.match?(reason) && body["transaction"].blank?
      end

      def settle_outcome(outcome, transaction: nil, response: {}, error_reason: nil)
        SettleResult.new(outcome:, transaction:, network: response["network"], payer: response["payer"], error_reason:, response:)
      end

      def post(path, payment, payment_requirements, read_timeout)
        body = {x402Version: payment["x402Version"] || payment[:x402Version], paymentPayload: payment, paymentRequirements: payment_requirements}
        body.to_json
        headers = authorization("POST", path)
        http = client(path, read_timeout)

        response = transport { http.post_with_response(body, headers) }
        parsed_answer(response.code.to_i, response.body)
      rescue LagoHttpClient::HttpError => e
        parsed_answer(e.error_code.to_i, e.error_body)
      end

      def get(path)
        headers = authorization("GET", path)
        http = client(path, READ_TIMEOUT)

        response = transport { http.get(headers:) }
        Answer.new(status: 200, body: response.is_a?(Hash) ? response : {}, parsed: response.is_a?(Hash))
      rescue LagoHttpClient::HttpError => e
        parsed_answer(e.error_code.to_i, e.error_body)
      rescue JSON::ParserError
        Answer.new(status: 200, body: {}, parsed: false)
      end

      def transport
        yield
      rescue LagoHttpClient::HttpError, JSON::ParserError
        raise
      rescue => e
        raise NoResponse, e.class.name
      end

      def parsed_answer(status, raw)
        parsed = JSON.parse(raw.presence || "{}")
        parsed.is_a?(Hash) ? Answer.new(status:, body: parsed, parsed: true) : Answer.new(status:, body: {}, parsed: false)
      rescue JSON::ParserError
        Answer.new(status:, body: {}, parsed: false)
      end

      def request_or_unavailable(operation)
        yield
      rescue NoResponse => e
        log_failure(operation, "no_response", error: e.message)
        raise UnavailableError, "#{operation}: #{e.message}"
      end

      def raise_for_access!(operation, answer)
        error_class, reason = case answer.status
        when 401 then [CredentialError, "unauthorized"]
        when 403 then [CredentialError, "forbidden"]
        when 429 then [RateLimitError, "rate_limited"]
        end
        return unless error_class

        log_failure(operation, reason, status: answer.status, correlation_id: answer.body["correlationId"])
        raise error_class.new("#{operation}: HTTP #{answer.status}", http_status: answer.status, error_type: answer.body["errorType"], correlation_id: answer.body["correlationId"])
      end

      def unavailable(operation, answer)
        log_failure(operation, answer.parsed ? "server_error" : "malformed_response", status: answer.status, correlation_id: answer.body["correlationId"])
        UnavailableError.new("#{operation}: HTTP #{answer.status}", http_status: answer.status, error_type: answer.body["errorType"], correlation_id: answer.body["correlationId"])
      end

      def log_failure(operation, reason, **details)
        context = {operation:, reason:, **details}.compact
        Rails.logger.warn("#{self.class.name} call failed #{context.map { |k, v| "#{k}=#{v}" }.join(" ")}")
      end

      def client(path, read_timeout)
        LagoHttpClient::Client.new("https://#{HOST}#{BASE_PATH}#{path}", open_timeout: OPEN_TIMEOUT, read_timeout:)
      end

      def authorization(method, path)
        token = Cdp::Jwt.generate(api_key_id:, api_key_secret:, request_method: method, request_host: HOST, request_path: "#{BASE_PATH}#{path}")
        {"Authorization" => "Bearer #{token}"}
      end
    end
  end
end
