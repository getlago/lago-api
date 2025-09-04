# frozen_string_literal: true

module Invoices
  module ProviderTaxes
    class PullTaxesAndApplyService < BaseService
      def initialize(invoice:)
        @invoice = invoice

        super
      end

      def call
        return result.not_found_failure!(resource: "invoice") unless invoice
        return result.not_found_failure!(resource: "integration_customer") unless customer.tax_customer
        return result unless invoice.pending? || invoice.draft?
        return result unless invoice.tax_pending?

        invoice.error_details.tax_error.discard_all
        taxes_result = if invoice.draft?
          Integrations::Aggregator::Taxes::Invoices::CreateDraftService.call(invoice:, fees: invoice.fees)
        else
          Integrations::Aggregator::Taxes::Invoices::CreateService.call(invoice:, fees: invoice.fees)
        end

        unless taxes_result.success?
          create_error_detail(taxes_result.error)
          invoice.tax_status = "failed"
          invoice.status = "failed" unless invoice.draft?
          invoice.save!

          return result
        end

        provider_taxes = taxes_result.fees

        finalize_result = Invoices::FinalizeAfterTaxesService.call(invoice:, provider_taxes:)
        finalize_result.raise_if_error!

        result.invoice = finalize_result.invoice
        result
      rescue ActiveRecord::RecordInvalid => e
        result.record_validation_failure!(record: e.record)
      rescue BaseService::FailedResult => e
        e.result
      end

      private

      attr_accessor :invoice

      def customer
        @customer ||= invoice.customer
      end

      def create_error_detail(error)
        error_result = ErrorDetails::CreateService.call(
          owner: invoice,
          organization: invoice.organization,
          params: {
            error_code: :tax_error,
            details: {
              tax_error: error.code
            }.tap do |details|
              details[:tax_error_message] = error.error_message if error.code == "validationError"
            end
          }
        )
        error_result.raise_if_error!
      end
    end
  end
end
