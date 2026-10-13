# frozen_string_literal: true

module CursorPagination
  # Cursor pagination of a list: passed as the `pagination:` argument of a query, it
  # selects keyset pagination instead of the offset one. Every parameter is validated
  # on initialization, so an invalid request fails before any SQL runs.
  class Cursor
    DEFAULT_LIMIT = 20
    LIMIT_RANGE = (1..100)
    # Offset pagination parameters. Ignoring them would hand the first page back for
    # every page number, and a client paging until an empty page would never stop.
    OFFSET_PARAMS = %i[page per_page].freeze
    # Longest `limit` echoed back in an error: anything longer is not a limit anyway.
    MAX_ECHOED_LIMIT_LENGTH = 20

    attr_reader :table, :sort, :limit, :after, :before, :key

    def self.from_params(params, table:, sort: DEFAULT_SORT)
      reject_offset_params!(params)

      new(
        table:,
        sort:,
        limit: params[:limit],
        after: params[:after],
        before: params[:before],
        include_total_count: params[:include_total_count]
      )
    end

    # Also called by the v2 lists that are not paginated anymore, with their own reason.
    def self.reject_offset_params!(params, reason: "replaced_by_cursor")
      offset_params = OFFSET_PARAMS.select { params.key?(it) }

      if offset_params.any?
        raise Error.new(code: Error::INVALID_PARAMETER, details: offset_params.index_with { {reason:} })
      end
    end

    # `table` is the table of the listed resource: a cursor minted for another table is
    # rejected, even when both resources render under the same name. `sort` is the one of
    # the endpoint: a cursor minted under another sort is rejected as expired.
    def initialize(table:, sort: DEFAULT_SORT, limit: nil, after: nil, before: nil, include_total_count: nil)
      CursorPagination.validate_sort!(sort)

      @table = table
      @sort = sort
      @limit = parse_limit(limit)
      @after = parse_token(after, :after)
      @before = parse_token(before, :before)
      @include_total_count = parse_include_total_count(include_total_count)

      validate_combination!
      @key = Token.decode(token, table:, sort:, param: token_param) if token
    end

    def direction
      if after
        :forward
      elsif before
        :backward
      else
        :first
      end
    end

    def backward?
      direction == :backward
    end

    def include_total_count?
      @include_total_count
    end

    def token
      after || before
    end

    private

    def token_param
      after ? :after : :before
    end

    # A silent clamp would return fewer rows than asked, which some clients read as
    # the end of the list, hence an error for any value out of range.
    def parse_limit(value)
      return DEFAULT_LIMIT if value.nil? || value == ""

      limit = if value.is_a?(Integer)
        value
      elsif value.is_a?(String) && value.match?(/\A\d+\z/)
        value.to_i
      end
      return limit if LIMIT_RANGE.cover?(limit)

      details = {allowed_range: "#{LIMIT_RANGE.first}..#{LIMIT_RANGE.last}"}
      if value.is_a?(String) && value.length <= MAX_ECHOED_LIMIT_LENGTH
        details = {value:, **details}
      end
      raise Error.new(code: Error::INVALID_LIMIT, details: {limit: details})
    end

    # Strict, like `limit`: a lenient cast would read any unknown value as true.
    def parse_include_total_count(value)
      case value
      when nil, "", false, "false"
        false
      when true, "true"
        true
      else
        raise Error.new(
          code: Error::INVALID_PARAMETER,
          details: {include_total_count: {reason: "not_a_boolean", allowed_values: %w[true false]}}
        )
      end
    end

    def parse_token(value, param)
      return if value.nil? || value == ""

      if value.is_a?(String)
        value
      else
        raise Error.new(code: Error::INVALID_CURSOR, details: {param => {reason: "malformed"}})
      end
    end

    def validate_combination!
      if after && before
        raise Error.new(
          code: Error::INVALID_CURSOR,
          details: {after: {reason: "exclusive_with_before"}, before: {reason: "exclusive_with_after"}}
        )
      end

      # Keeps the count to one request per iteration: a client resuming from a stored
      # cursor gets the total from a fresh first page.
      if include_total_count? && token
        raise Error.new(
          code: Error::TOTAL_COUNT_FIRST_PAGE_ONLY,
          details: {include_total_count: {reason: "first_page_only"}}
        )
      end
    end
  end
end
