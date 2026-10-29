# frozen_string_literal: true

# Keyset pagination of the v2 lists. Named apart from the offset pagination concern
# (`Pagination`), which keeps serving v1 and GraphQL.
module CursorPagination
  # The sort of a cursor-paginated list, unless its endpoint declares another. Immutable
  # and NOT NULL columns only, so that no row moves while a client iterates; the last
  # column only breaks ties, and its direction is invisible to clients since both ids and
  # random tiebreaks are opaque.
  #
  # A sort is one or more date or time columns, then a tiebreak column, in the same
  # single direction: a single row-value comparison then bounds a page, and a
  # `(…, <time> DESC, <tiebreak> DESC)` index serves it. Mixed directions would need an
  # OR-chain predicate. A keyset query replaces the ordering of the query anyway, so the
  # offset lists keep theirs. The tiebreak is a UUID `id` on the Postgres lists, a string
  # business id on the ClickHouse log lists.
  DEFAULT_SORT = {created_at: :desc, id: :desc}.freeze

  # The type `Token` writes and reads a column's value as. Any other column is a string.
  COLUMN_TYPES = {issuing_date: :date, created_at: :time, logged_at: :time, id: :uuid}.freeze

  DIRECTIONS = %i[asc desc].freeze

  def self.column_type(column)
    COLUMN_TYPES.fetch(column, :string)
  end

  # Written in every cursor: a cursor minted under another sort is rejected as expired.
  def self.signature(sort)
    sort.map { |column, direction| "#{column}:#{direction}" }.join(",")
  end

  # A programming error rather than a client one: the endpoint declares its sort, and a
  # cursor can only be resumed on the columns its key holds, in a single direction.
  def self.validate_sort!(sort)
    *columns, tiebreak = sort.keys
    directions = sort.values.uniq
    supported = columns.any? &&
      columns.all? { %i[date time].include?(column_type(it)) } &&
      %i[uuid string].include?(column_type(tiebreak)) &&
      directions.one? && DIRECTIONS.include?(directions.first)

    raise ArgumentError, "unsupported cursor sort #{sort.inspect}: date or time columns, then a tiebreak, in a single direction" unless supported
  end
end
