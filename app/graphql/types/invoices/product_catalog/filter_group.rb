# frozen_string_literal: true

module Types
  module Invoices
    module ProductCatalog
      class FilterGroup < Types::BaseObject
        graphql_name "InvoiceProductCatalogFilterGroup"

        field :product_filter, Types::ProductFilters::Object, null: false, method: :filter

        field :amount_cents, GraphQL::Types::BigInt, null: false
        field :fees_count, Integer, null: false
      end
    end
  end
end
