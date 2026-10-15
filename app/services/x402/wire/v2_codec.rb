# frozen_string_literal: true

module X402
  module Wire
    module V2Codec
      PAYMENT_REQUIRED = "PAYMENT-REQUIRED"
      PAYMENT_SIGNATURE = "PAYMENT-SIGNATURE"
      PAYMENT_RESPONSE = "PAYMENT-RESPONSE"
      MIME_TYPE = "application/json"

      def self.encode(object)
        Base64.strict_encode64(JSON.generate(object))
      end

      def self.decode(header)
        decoded = JSON.parse(Base64.strict_decode64(header.to_s))
        decoded if decoded.is_a?(Hash)
      rescue ArgumentError, JSON::ParserError
        nil
      end

      def self.requirement(requirement)
        {
          "scheme" => requirement[:scheme],
          "network" => requirement[:network],
          "amount" => requirement[:amount_atomic],
          "asset" => requirement[:asset_address],
          "payTo" => requirement[:pay_to],
          "maxTimeoutSeconds" => requirement[:max_timeout_seconds],
          "extra" => requirement[:extra]
        }
      end

      def self.payment_required(requirements:, resource:, error: nil)
        {
          "x402Version" => X402::PaymentPayload::X402_VERSION,
          "error" => error,
          "resource" => resource,
          "accepts" => requirements.map { |requirement| requirement(requirement) }
        }.compact
      end

      def self.invoice_resource(invoice)
        {"url" => invoice.x402_payment_url, "description" => "Invoice #{invoice.number}", "mimeType" => MIME_TYPE}
      end

      def self.settlement_response(settlement)
        {
          "success" => true,
          "transaction" => settlement.transaction_hash,
          "network" => settlement.network,
          "payer" => settlement.payer_address
        }
      end
    end
  end
end
