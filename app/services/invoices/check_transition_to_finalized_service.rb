# frozen_string_literal: true

module Invoices
  class CheckTransitionToFinalizedService < BaseService
    def initialize(invoice:)
      @invoice = invoice
      @customer = @invoice.customer
      @organization = @customer.organization
      super
    end

    def call
      if should_finalize_invoice?
        invoice.update(status: :finalized)
      else
        invoice.update(status: :closed)
      end
      result.invoice = invoice
      result
    end

    private

    attr_reader :invoice, :customer, :organization

    def should_finalize_invoice?
      return true unless invoice.fees_amount_cents.zero?
      customer_setting = customer.finalize_zero_amount_invoice
      if customer_setting == 'inherit'
        organization.finalize_zero_amount_invoice
      else
        customer_setting == 'finalize'
      end
    end
  end
end
