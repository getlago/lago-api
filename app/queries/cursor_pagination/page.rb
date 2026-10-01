# frozen_string_literal: true

module CursorPagination
  # One page of a keyset-paginated relation: loads it once, drops the extra row fetched
  # by `Keyset`, restores the list order when paging backward, and builds the cursors.
  class Page
    attr_reader :cursor

    def initialize(records:, cursor:)
      @relation = records
      @cursor = cursor
    end

    def records
      load_records unless defined?(@records)
      @records
    end

    # Runs the count when the cursor asks for the total, once per page.
    def meta
      cursors = {next_cursor:, prev_cursor:}

      if cursor.include_total_count?
        cursors.merge(total_count_meta)
      else
        cursors
      end
    end

    private

    attr_reader :relation

    def load_records
      ensure_keyset_order!
      rows = relation.to_a
      @has_more = rows.size > cursor.limit

      rows = rows.first(cursor.limit)
      rows.reverse! if cursor.backward?
      @records = rows
    end

    # The cursors encode the keyset order, so the rows must be read in it: an order a query
    # appends after `paginate` would page on one order while the cursors walk another.
    def ensure_keyset_order!
      expected = relation.klass.unscoped.reorder(Keyset.order(cursor)).order_values

      if relation.order_values != expected
        raise ArgumentError, "#{relation.klass} is ordered after its keyset: `paginate` must be the last scope operation"
      end
    end

    def has_more?
      records
      @has_more
    end

    # An empty page only happens after deletions. The cursor pointing back echoes the
    # incoming one, used as a strict bound, so the anchor row is not returned again.
    def next_cursor
      case cursor.direction
      when :first, :forward
        encode(records.last) if has_more?
      when :backward
        records.empty? ? cursor.before : encode(records.last)
      end
    end

    def prev_cursor
      case cursor.direction
      when :forward
        records.empty? ? cursor.after : encode(records.first)
      when :backward
        encode(records.first) if has_more?
      end
    end

    # Counts the page's own relation. A count is only allowed on the first page, where the
    # keyset adds nothing but its order and limit, which the count drops: it then counts
    # exactly the rows of the list, with the same filters as the page.
    def total_count_meta
      raise ArgumentError, "a total count is only computed on the first page" unless cursor.direction == :first

      @total_count ||= TotalCount.call(relation)

      if @total_count.estimated
        {total_count: [@total_count.value, rows_seen].max, total_count_estimated: true}
      else
        {total_count: @total_count.value}
      end
    end

    # The rows of the first page, plus the one fetched past it, are a lower bound of the
    # total that an estimate must not undercut.
    def rows_seen
      records.size + (has_more? ? 1 : 0)
    end

    def encode(record)
      Token.encode(table: cursor.table, record:, sort: cursor.sort)
    end
  end
end
