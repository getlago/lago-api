# frozen_string_literal: true

module Invoices
  class TransitionToFinalStatusService < BaseService
    def initialize(invoice:)
      @invoice = invoice
      @customer = @invoice.customer
      @billing_entity = @customer.billing_entity
      super
    end

    def call
      if should_finalize_invoice?
        Invoices::FinalizeService.call!(invoice: invoice)
      else
        invoice.status = :closed
      end
      result.invoice = invoice
      result
    end

    def should_finalize_invoice?
      return true unless invoice.fees_amount_cents.zero?
      customer_setting = customer.finalize_zero_amount_invoice
      if customer_setting == "inherit"
        billing_entity.finalize_zero_amount_invoice
      else
        customer_setting == "finalize"
      end
    end

    private

    attr_reader :invoice, :customer, :billing_entity
  end
end
