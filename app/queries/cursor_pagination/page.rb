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

    def meta
      {next_cursor:, prev_cursor:}
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

    def encode(record)
      Token.encode(table: cursor.table, record:, sort: cursor.sort)
    end
  end
end
