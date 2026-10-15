# frozen_string_literal: true

# Keyset pagination of the v2 lists. Named apart from the offset pagination concern
# (`Pagination`), which keeps serving v1 and GraphQL.
module CursorPagination
  # The sort of a cursor-paginated list, unless its endpoint declares another. Immutable
  # and NOT NULL columns only, so that no row moves while a client iterates; `id` only
  # breaks ties, and its direction is invisible to clients since ids are random.
  #
  # Both columns run in the same direction, unlike the `id ASC` tie-break that
  # `BaseQuery#apply_consistent_ordering` gives the offset lists: a single row-value
  # comparison then bounds a page, and a `(…, created_at DESC, id DESC)` index serves it.
  # Mixed directions would need an OR-chain predicate. A keyset query replaces the
  # ordering of the query anyway, so the offset lists keep theirs.
  DEFAULT_SORT = {created_at: :desc, id: :desc}.freeze

  # The columns of a cursor key. A sort on other columns needs typed keys first.
  SORT_COLUMNS = %i[created_at id].freeze

  # Written in every cursor: a cursor minted under another sort is rejected as expired.
  def self.signature(sort)
    sort.map { |column, direction| "#{column}:#{direction}" }.join(",")
  end

  # A programming error rather than a client one: the endpoint declares its sort, and a
  # cursor can only be resumed on the columns its key holds, in a single direction.
  def self.validate_sort!(sort)
    directions = sort.values.uniq
    supported = sort.keys == SORT_COLUMNS && directions.size == 1 && %i[asc desc].include?(directions.first)

    raise ArgumentError, "unsupported cursor sort #{sort.inspect}: created_at then id, in a single direction" unless supported
  end
end
