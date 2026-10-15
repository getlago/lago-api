# frozen_string_literal: true

module X402
  module Invoices
    class MintPaymentLinkService < BaseService
      Result = BaseResult[:invoice]

      def initialize(invoice:, connection_code:)
        @invoice = invoice
        @connection_code = connection_code

        super
      end

      def call
        return result.forbidden_failure! unless invoice.organization.x402_payments_enabled?
        return result.single_validation_failure!(field: :connection_code, error_code: "value_is_mandatory") if connection_code.blank?
        return result.not_found_failure!(resource: "connection") unless connection

        refusal = invoice.x402_payment_refusal
        return result.single_validation_failure!(error_code: refusal) if refusal

        invoice.with_lock do
          invoice.update!(x402_payment_token: SecureRandom.hex(32), x402_connection: connection) unless bound_to_connection?
        end

        result.invoice = invoice
        result
      end

      private

      attr_reader :invoice, :connection_code

      def connection
        @connection ||= invoice.organization.x402_connections.find_by(code: connection_code)
      end

      def bound_to_connection?
        invoice.x402_payment_token.present? && invoice.x402_connection_id == connection.id
      end
    end
  end
end
