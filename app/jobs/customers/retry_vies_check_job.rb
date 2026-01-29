# frozen_string_literal: true

module Customers
  class RetryViesCheckJob < ApplicationJob
    queue_as :default

    def perform(customer_id)
      customer = Customer.find(customer_id)

      # VIES failures are handled by the service which schedules its own retry
      eu_auto_taxes_result = Customers::EuAutoTaxesService.call(
        customer: customer,
        new_record: false,
        tax_attributes_changed: true
      )

      # If VIES failed, the service already scheduled a retry
      return unless eu_auto_taxes_result.success?

      Customers::ApplyTaxesService.call(
        customer: customer,
        tax_codes: [eu_auto_taxes_result.tax_code]
      )

      # Finalize any invoices that were blocked by VIES
      enqueue_pending_invoice_finalization(customer)
    end

    private

    def enqueue_pending_invoice_finalization(customer)
      customer.invoices.pending.where(tax_status: "pending").find_each do |invoice|
        Invoices::FinalizePendingViesInvoiceJob.perform_later(invoice)
      end
    end
  end
end
