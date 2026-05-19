# frozen_string_literal: true

module PaymentProviders
  module Paystack
    class Client
      class Error < StandardError
        attr_reader :code, :response

        def initialize(message:, code: "paystack_error", response: nil)
          @code = code
          @response = response

          super(message)
        end
      end

      def initialize(payment_provider:)
        @payment_provider = payment_provider
      end

      def create_customer(payload)
        post("/customer", payload)
      end

      def update_customer(customer_code, payload)
        put("/customer/#{customer_code}", payload)
      end

      def initialize_transaction(payload)
        post("/transaction/initialize", payload)
      end

      def verify_transaction(reference)
        get("/transaction/verify/#{reference}")
      end

      def charge_authorization(payload)
        post("/transaction/charge_authorization", payload)
      end

      def create_refund(payload)
        post("/refund", payload)
      end

      def fetch_refund(id)
        get("/refund/#{id}")
      end

      def retry_refund(id, refund_account_details:)
        post(
          "/refund/retry_with_customer_details/#{id}",
          {refund_account_details:}
        )
      end

      private

      attr_reader :payment_provider

      def post(path, payload)
        parse_response(http_client(path).post_with_response(payload, headers))
      end

      def put(path, payload)
        parse_response(http_client(path).put_with_response(payload, headers))
      end

      def get(path)
        parse_payload(http_client(path).get(headers:))
      end

      def parse_response(response)
        parse_payload(JSON.parse(response.body.presence || "{}"))
      rescue JSON::ParserError
        raise Error.new(message: "Invalid Paystack response", response: response.body)
      end

      def parse_payload(parsed_response)
        if parsed_response["status"] == false
          raise Error.new(
            message: parsed_response["message"].presence || "Paystack request failed",
            response: parsed_response
          )
        end

        parsed_response
      end

      def http_client(path)
        LagoHttpClient::Client.new("#{payment_provider.api_url}#{path}")
      end

      def headers
        {
          "Authorization" => "Bearer #{payment_provider.secret_key}",
          "Content-Type" => "application/json",
          "Accept" => "application/json"
        }
      end
    end
  end
end
