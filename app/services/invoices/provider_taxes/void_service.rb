# frozen_string_literal: true

module Invoices
  module ProviderTaxes
    class VoidService < BaseService
      def initialize(invoice:)
        @invoice = invoice

        super
      end

      def call
        return result.not_found_failure!(resource: 'invoice') if invoice.blank?

        invoice.error_details.tax_voiding_error.discard_all

        tax_result = Integrations::Aggregator::Taxes::Invoices::VoidService.new(invoice:).call

        if frozen_transaction?(tax_result)
          negate_result = perform_invoice_negate

          unless negate_result.success?
            return result.validation_failure!(errors: {tax_error: [negate_result.error.code]})
          end
        elsif !tax_result.success?
          create_error_detail(tax_result.error.code)

          return result.validation_failure!(errors: {tax_error: [tax_result.error.code]})
        end

        result.invoice = invoice

        result
      end

      private

      attr_reader :invoice

      delegate :customer, to: :invoice

      def perform_invoice_negate
        negate_result = Integrations::Aggregator::Taxes::Invoices::NegateService.new(invoice:).call

        create_error_detail(negate_result.error.code) unless negate_result.success?

        negate_result
      end

      def create_error_detail(code)
        error_result = ErrorDetails::CreateService.call(
          owner: invoice,
          organization: invoice.organization,
          params: {
            error_code: :tax_voiding_error,
            details: {
              tax_voiding_error: code
            }
          }
        )
        error_result.raise_if_error!
      end

      # transactionFrozenForFiling error means that tax is already reported to the tax authority
      # We should call negate action instead
      def frozen_transaction?(tax_result)
        !tax_result.success? && tax_result.error.code == 'transactionFrozenForFiling'
      end
    end
  end
end
