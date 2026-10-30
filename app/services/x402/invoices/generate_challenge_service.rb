# frozen_string_literal: true

module X402
  module Invoices
    class GenerateChallengeService < BaseService
      Result = BaseResult[:requirements]

      def initialize(invoice:)
        @invoice = invoice

        super
      end

      def call
        refusal = invoice.x402_payment_refusal
        return result.single_validation_failure!(error_code: refusal) if refusal
        return result.not_found_failure!(resource: "connection") unless invoice.x402_connection
        return result.single_validation_failure!(field: :connection_code, error_code: "environment_not_enabled") unless invoice.x402_connection.environment_enabled?

        requirements = X402::PaymentRequirementsService.call(connection: invoice.x402_connection, amount_cents: invoice.total_due_amount_cents)

        if requirements.success?
          result.requirements = requirements.requirements
          result
        else
          result.fail_with_error!(requirements.error)
        end
      end

      private

      attr_reader :invoice
    end
  end
end
