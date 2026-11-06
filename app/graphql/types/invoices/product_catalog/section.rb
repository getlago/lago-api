# frozen_string_literal: true

module Types
  module Invoices
    module ProductCatalog
      class Section < Types::BaseObject
        graphql_name "InvoiceProductCatalogSection"

        field :product_category, Types::ProductCategories::Object, null: true, method: :category
        field :products, [Types::Invoices::ProductCatalog::ProductGroup], null: false
      end
    end
  end
end
