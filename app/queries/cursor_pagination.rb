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

  # The columns a sort can order on before its tiebreak, with the type `Token` writes and
  # reads their value as.
  KEY_COLUMNS = {issuing_date: :date, created_at: :time, logged_at: :time}.freeze

  # Written in every cursor: a cursor minted under another sort is rejected as expired.
  def self.signature(sort)
    sort.map { |column, direction| "#{column}:#{direction}" }.join(",")
  end

  # A programming error rather than a client one: the endpoint declares its sort. It ends
  # with a unique tiebreak, so that two rows never tie: `id` on the Postgres lists, a string
  # business id on the ClickHouse log lists.
  def self.validate_sort!(sort)
    *columns, tiebreak = sort.keys
    supported = columns.any? &&
      columns.all? { KEY_COLUMNS.key?(it) } &&
      !KEY_COLUMNS.key?(tiebreak) &&
      sort.values.all? { %i[asc desc].include?(it) }

    raise ArgumentError, "unsupported cursor sort #{sort.inspect}: columns among #{KEY_COLUMNS.keys.join(", ")}, then a unique tiebreak, each asc or desc" unless supported
  end
end
