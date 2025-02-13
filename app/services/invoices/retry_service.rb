# frozen_string_literal: true

module Invoices
  class RetryService < BaseService
    def initialize(invoice:)
      @invoice = invoice

      super
    end

    def call
      return result.not_found_failure!(resource: "invoice") unless invoice
      return result.not_allowed_failure!(code: "invalid_status") unless invoice.failed?

      invoice.status = "pending"
      invoice.tax_status = "pending"
      invoice.save!

      Invoices::ProviderTaxes::PullTaxesAndApplyJob.perform_later(invoice:)

      result.invoice = invoice
      result
    end

    private

    attr_accessor :invoice
  end
end
