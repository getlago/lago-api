# frozen_string_literal: true

module X402
  module Facilitator
    class Error < StandardError
      attr_reader :http_status, :error_type, :correlation_id

      def initialize(message = nil, http_status: nil, error_type: nil, correlation_id: nil)
        @http_status = http_status
        @error_type = error_type
        @correlation_id = correlation_id
        super(message)
      end
    end

    class CredentialError < Error; end

    class RateLimitError < Error; end

    class UnavailableError < Error; end

    class VerifyResult < Data.define(:valid, :payer, :invalid_reason, :response)
      def valid?
        valid
      end
    end

    class SettleResult < Data.define(:outcome, :transaction, :network, :payer, :error_reason, :response)
      PENDING_OUTCOMES = %i[unconfirmed_failure settlement_pending server_error no_response].freeze
      OUTCOMES = [:settled, :failed, *PENDING_OUTCOMES].freeze

      def initialize(outcome:, **)
        raise ArgumentError, "unknown settle outcome: #{outcome.inspect}" unless OUTCOMES.include?(outcome)

        super
      end

      def settled?
        outcome == :settled
      end

      def failed?
        outcome == :failed
      end

      def pending?
        PENDING_OUTCOMES.include?(outcome)
      end
    end

    class SupportedResult < Data.define(:kinds, :response)
      def supports?(network:, scheme: "exact", x402_version: 2)
        kinds.any? { |kind| kind["network"] == network && kind["scheme"] == scheme && kind["x402Version"] == x402_version }
      end

      def fee_payer(network:)
        kinds.find { |kind| kind["network"] == network }&.dig("extra", "feePayer")
      end
    end
  end
end
