# frozen_string_literal: true

module Types
  module Invoices
    module AppliedTaxes
      class Object < Types::BaseObject
        graphql_name 'InvoiceAppliedTax'
        implements Types::Taxes::AppliedTax

        field :applied_on_whole_invoice, GraphQL::Types::Boolean, null: false, method: :applied_on_whole_invoice?
        field :fees_amount_cents, GraphQL::Types::BigInt, null: false
        field :invoice, Types::Invoices::Object, null: false
      end
    end
  end
end
