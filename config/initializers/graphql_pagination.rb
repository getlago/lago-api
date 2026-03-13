# frozen_string_literal: true

# Extend CollectionMetadataType with a cursor field
# to support cursor-based pagination across all collection types.
GraphqlPagination::CollectionMetadataType.field(
  :cursor,
  String,
  null: true,
  description: "Cursor for the last record on the current page"
)

GraphqlPagination::CollectionMetadataType.define_method(:cursor) do
  object.try(:cursor)
end
