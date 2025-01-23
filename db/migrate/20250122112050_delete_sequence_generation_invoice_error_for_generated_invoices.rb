# frozen_string_literal: true

class DeleteSequenceGenerationInvoiceErrorForGeneratedInvoices < ActiveRecord::Migration[7.1]
  GENERATED_INVOICE_STATUSES = [1, 6].freeze

  def change
    InvoiceError.joins("LEFT JOIN invoices ON invoices.id = invoice_errors.id")
      .where("invoice_errors.backtrace LIKE ?", "%generate_organization_sequential_id%")
      .where(invoices: {status: GENERATED_INVOICE_STATUSES}).find_each do |ie|
      ie.delete
    end
  end
end
