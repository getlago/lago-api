# frozen_string_literal: true

module Types
  module Invoices
    module ProductCatalog
      class Contract < Types::BaseObject
        graphql_name "InvoiceProductCatalogContract"

        field :contract, Types::Contracts::Object, null: false
        field :product_catalog_sections, [Types::Invoices::ProductCatalog::Section], null: false, method: :sections
      end
    end
  end
end
