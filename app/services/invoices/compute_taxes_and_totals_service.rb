# frozen_string_literal: true

module Invoices
  class ComputeTaxesAndTotalsService < BaseService
    def initialize(invoice:, finalizing: true)
      @invoice = invoice
      @finalizing = finalizing

      super
    end

    def call
      return result.not_found_failure!(resource: "invoice") unless invoice

      if customer_provider_taxation? && invoice.should_apply_provider_tax?
        invoice.status = "pending" if finalizing
        invoice.tax_status = "pending"
        invoice.save!
        after_commit { Invoices::ProviderTaxes::PullTaxesAndApplyJob.perform_later(invoice:) }

        return result.unknown_tax_failure!(code: "tax_error", message: "unknown taxes")
      else
        Invoices::ComputeAmountsFromFees.call(invoice:)
      end

      result.invoice = invoice
      result
    end

    private

    attr_reader :invoice, :finalizing

    def customer_provider_taxation?
      @customer_provider_taxation ||= invoice.customer.tax_customer
    end
  end
end
