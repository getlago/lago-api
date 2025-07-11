# frozen_string_literal: true

module Types
  module Invoices
    class VoidedInvoiceFeeInput < BaseInputObject
      description "Fee input for creating or updating invoice from voided invoice"

      argument :id, ID, required: false

      argument :add_on_id, ID, required: false
      argument :charge_id, ID, required: false
      argument :description, String, required: false
      argument :invoice_display_name, String, required: false
      argument :name, String, required: false
      argument :subscription_id, ID, required: false
      argument :tax_codes, [String], required: false
      argument :total_aggregated_units, GraphQL::Types::Float, required: false
      argument :unit_amount_cents, GraphQL::Types::BigInt, required: false
      argument :units, GraphQL::Types::Float, required: false
    end
  end
end
