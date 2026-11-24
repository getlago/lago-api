# frozen_string_literal: true

module Types
  module Invoices
    module ProductCatalog
      class ProductGroup < Types::BaseObject
        graphql_name "InvoiceProductCatalogProductGroup"

        field :product, Types::Products::Object, null: false

        field :amount_cents, GraphQL::Types::BigInt, null: false
        field :fees_count, Integer, null: false

        field :filters, [Types::Invoices::ProductCatalog::FilterGroup], null: false
      end
    end
  end
end
