# frozen_string_literal: true

module Types
  module Invoices
    class RegenerateInvoiceFeeInput < Types::BaseInputObject
      graphql_name "RegenerateInvoiceFeeInput"
      description "Input for creating or updating fees when regenerating an invoice"

      argument :fee_id, ID, required: false, description: "ID of an existing fee to update"
      argument :charge_id, ID, required: false, description: "Charge ID used when creating a new fee"
      argument :subscription_id, ID, required: false, description: "Subscription ID used when creating a new fee"
      argument :units, GraphQL::Types::Float, required: true, description: "Number of units for the fee"
      argument :unit_precise_amount, String, required: false, description: "Precise unit amount as string"
      argument :invoice_display_name, String, required: false, description: "Display name for the invoice line"
    end
  end
end
