# frozen_string_literal: true

module Customers
  class RetryViesCheckJob < ApplicationJob
    queue_as :default

    def perform(customer_id)
      customer = Customer.find(customer_id)
      return if customer.tax_identification_number.blank?

      # Re-run the EU auto taxes service
      tax_code = Customers::EuAutoTaxesService.call!(
        customer: customer,
        new_record: false,
        tax_attributes_changed: true
      ).tax_code

      # If successful, apply the tax code
      if tax_code.present?
        Customers::ApplyTaxesService.call(
          customer: customer,
          tax_codes: [tax_code]
        )
      end

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
