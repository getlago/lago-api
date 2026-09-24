# frozen_string_literal: true

module X402
  module Facilitator
    # CDP's hosted x402 facilitator. Forwards the payment and its requirements unchanged, in their own x402
    # version (D7); never resends a settle and never trusts the hash of a failed one (§5.4).
    class CoinbaseCdpAdapter
      HOST = "api.cdp.coinbase.com"
      BASE_PATH = "/platform/v2/x402"
      OPEN_TIMEOUT = 5
      VERIFY_READ_TIMEOUT = 15
      SETTLE_READ_TIMEOUT = 20 # D10: a hard client timeout well under maxTimeoutSeconds.
      AMBIGUOUS_ERRORS = [Net::OpenTimeout, Net::ReadTimeout, Errno::ECONNRESET, EOFError, OpenSSL::SSL::SSLError].freeze

      VerifyResult = Data.define(:valid, :payer, :invalid_reason, :response)
      SettleResult = Data.define(:status, :transaction, :network, :payer, :error_reason, :response)

      def initialize(connection:)
        @connection = connection
      end

      def verify(payment:, payment_requirements:)
        response = post("/verify", payment:, payment_requirements:, read_timeout: VERIFY_READ_TIMEOUT)

        VerifyResult.new(
          valid: response["isValid"] == true,
          payer: response["payer"],
          invalid_reason: response["invalidReason"].presence || response["errorType"].presence || "verify_failed",
          response:
        )
      end

      # :settled; :failed — terminal, nothing moved; :pending — unconfirmed, the money may have moved (§5.1, §5.6).
      def settle(payment:, payment_requirements:)
        response = post("/settle", payment:, payment_requirements:, read_timeout: SETTLE_READ_TIMEOUT)
        status = settle_status(response)

        SettleResult.new(
          status:,
          transaction: (status == :failed) ? nil : response["transaction"].presence,
          network: response["network"],
          payer: response["payer"],
          error_reason: response["errorReason"],
          response:
        )
      rescue *AMBIGUOUS_ERRORS => e
        SettleResult.new(status: :pending, transaction: nil, network: nil, payer: nil, error_reason: e.class.name, response: {})
      end

      private

      attr_reader :connection

      def settle_status(response)
        if response["success"] == true
          :settled
        elsif response["errorReason"] == "settlement_pending" || response["httpStatus"].to_i >= 500
          :pending
        else
          :failed
        end
      end

      def post(path, payment:, payment_requirements:, read_timeout:)
        client = LagoHttpClient::Client.new("https://#{HOST}#{BASE_PATH}#{path}", open_timeout: OPEN_TIMEOUT, read_timeout:)
        body = {x402Version: payment["x402Version"], paymentPayload: payment, paymentRequirements: payment_requirements}

        parse(client.post_with_response(body, {"Authorization" => "Bearer #{jwt(path)}"}).body)
      rescue LagoHttpClient::HttpError => e
        # CDP answers settlement_pending as an HTTP 500 with a JSON body (§5.1) and rejections as 4xx.
        parse(e.error_body).merge("httpStatus" => e.error_code.to_i)
      end

      def parse(body)
        JSON.parse(body.presence || "{}")
      rescue JSON::ParserError
        {}
      end

      def jwt(path)
        X402::Cdp::Jwt.generate(
          api_key_id: connection.cdp_api_key_id,
          api_key_secret: connection.cdp_api_key_secret,
          request_method: "POST",
          request_host: HOST,
          request_path: "#{BASE_PATH}#{path}"
        )
      end
    end
  end
end
