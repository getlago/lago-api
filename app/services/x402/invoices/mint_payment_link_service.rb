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
        return result.single_validation_failure!(field: :connection_code, error_code: "environment_not_enabled") unless connection.environment_enabled?

        invoice.with_lock do
          refusal = invoice.x402_payment_refusal

          if refusal
            result.single_validation_failure!(error_code: refusal)
          elsif downgrade?
            result.single_validation_failure!(field: :connection_code, error_code: "invoice_bound_to_mainnet")
          elsif !bound_to_connection?
            invoice.update!(x402_payment_token: SecureRandom.hex(32), x402_connection: connection)
          end
        end

        result.invoice = invoice if result.success?
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

      def downgrade?
        !connection.mainnet? &&
          invoice.organization.x402_connections.with_discarded.where(id: invoice.x402_connection_id).any?(&:mainnet?)
      end
    end
  end
end
