# frozen_string_literal: true

module Types
  module Invoices
    module ProductCatalog
      class FilterGroup < Types::BaseObject
        graphql_name "InvoiceProductCatalogFilterGroup"

        field :product_filter, Types::ProductFilters::Object, null: false, method: :filter

        field :amount_cents, GraphQL::Types::BigInt, null: false
        field :fees_count, Integer, null: false

        def amount_cents
          ProductCatalogHierarchyHelper.total(object.entries)
        end

        def fees_count
          object.entries.size
        end
      end
    end
  end
end
