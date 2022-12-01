# frozen_string_literal: true

module Clock
  class FinalizeInvoicesJob < ApplicationJob
    queue_as 'clock'

    def perform
      draft_invoices.each do |invoice|
        Invoices::FinalizeService.call(invoice: invoice)
      end
    end

    private

    def draft_invoices
      Invoice
        .draft
        .joins(customer: :organization)
        .where(
          "(invoices.created_at + \
          COALESCE(customers.invoice_grace_period, organizations.invoice_grace_period) * INTERVAL '1 DAY') \
          < ?",
          Time.current,
        )
    end
  end
end
