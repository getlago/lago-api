# frozen_string_literal: true

module Types
  module Invoices
    class CreateInvoiceInput < BaseInputObject
      description "Create Invoice input arguments"

      argument :currency, Types::CurrencyEnum, required: false
      argument :customer_id, ID, required: true
      argument :fees, [Types::Invoices::FeeInput], required: true
      argument :voided_invoice_id, ID, required: false
    end
  end
end
