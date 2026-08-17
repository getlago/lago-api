# frozen_string_literal: true

module Types
  module Invoices
    class CollectionMetadata < GraphqlPagination::CollectionMetadataType
      graphql_name "InvoiceCollectionMetadata"
      description "Pagination metadata for a collection of invoices"

      field :has_next_page, Boolean, null: false,
        description: "True when another page follows, even when `totalCount` is capped"
      field :total_count_capped, Boolean, null: false,
        description: "True when `totalCount` hit the counting limit and is a lower bound, not the exact total"

      def has_next_page
        return object.has_next_page? if object.respond_to?(:has_next_page?)

        object.current_page < object.total_pages
      end

      def total_count_capped
        object.respond_to?(:capped_total_count?) && object.capped_total_count?
      end
    end
  end
end
