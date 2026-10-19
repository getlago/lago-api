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
  # A keyset query replaces the ordering of the query anyway, so the offset lists keep
  # theirs. An endpoint whose index serves the offset order declares that sort instead.
  DEFAULT_SORT = {created_at: :desc, id: :desc}.freeze

  # The columns a sort can use, in the order it lists them. `Token` knows how to write each
  # one in a cursor key.
  SORT_COLUMNS = %i[issuing_date created_at id].freeze

  # Written in every cursor: a cursor minted under another sort is rejected as expired.
  def self.signature(sort)
    sort.map { |column, direction| "#{column}:#{direction}" }.join(",")
  end

  # A programming error rather than a client one: the endpoint declares its sort. It ends
  # with `id`, the only unique column, so that two rows never tie.
  def self.validate_sort!(sort)
    columns = sort.keys
    supported = columns.size > 1 &&
      (SORT_COLUMNS & columns) == columns &&
      columns.last == :id &&
      sort.values.all? { %i[asc desc].include?(it) }

    raise ArgumentError, "unsupported cursor sort #{sort.inspect}: columns among #{SORT_COLUMNS.join(", ")} in that order, id last, each asc or desc" unless supported
  end
end
