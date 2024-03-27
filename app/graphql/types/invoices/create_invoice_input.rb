# frozen_string_literal: true

module Types
  module Invoices
    class CreateInvoiceInput < BaseInputObject
      description "Create Invoice input arguments"

      argument :currency, Types::CurrencyEnum, required: false
      argument :customer_id, ID, required: true
      argument :fees, [Types::Invoices::FeeInput], required: true
    end
  end
end
