# frozen_string_literal: true

module Invoices
  class GetProviderTaxesService < BaseService
    def initialize(invoice:, fees: nil)
      @invoice = invoice
      @provider_taxes = provider_taxes || fetch_provider_taxes_result.fees

      super
    end

    def call
      taxes_result = Integrations::Aggregator::Taxes::Invoices::CreateService.call(invoice:, fees: fees_result)

      unless taxes_result.success?
        result.validation_failure!(errors: {tax_error: [taxes_result.error.code]})
        create_error_detail(taxes_result.error.code)

        return result
      end
      result.fetched_taxes = fetched_taxes
      result.fees = fetched_taxes.fees
    end

    private

    def create_error_detail(code)
      error_result = ErrorDetails::CreateService.call(
        owner: invoice,
        organization: invoice.organization,
        params: {
          error_code: :tax_error,
          details: {
            tax_error: code
          }
        }
      )
      error_result.raise_if_error!
    end

  end
end
