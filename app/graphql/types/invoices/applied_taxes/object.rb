# frozen_string_literal: true

module Types
  module Invoices
    module AppliedTaxes
      class Object < Types::BaseObject
        graphql_name 'InvoiceAppliedTax'
        implements Types::Taxes::AppliedTax

        field :invoice, Types::Invoices::Object, null: false
      end
    end
  end
end
