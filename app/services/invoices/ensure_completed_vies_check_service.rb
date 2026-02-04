# frozen_string_literal: true

module Invoices
  class EnsureCompletedViesCheckService < BaseService
    def initialize(invoice:, finalizing: true)
      @invoice = invoice
      @customer = invoice&.customer
      @finalizing = finalizing

      super
    end

    def call
      return result.not_found_failure!(resource: "invoice") unless invoice

      # VIES does not apply if EU tax management is disabled
      return result unless customer.billing_entity.eu_tax_management?

      # VIES is irrelevant for provider tax customers
      return result if customer_provider_taxation?

      # Check if VIES validation is pending
      return result unless customer.vies_check_in_progress?

      invoice.status = :pending if finalizing
      invoice.tax_status = :pending
      invoice.save!

      result.unknown_tax_failure!(code: "vies_check_pending", message: "VIES validation pending")
    end

    private

    attr_reader :invoice, :customer, :finalizing

    def customer_provider_taxation?
      customer.tax_customer.present?
    end
  end
end
