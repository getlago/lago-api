# frozen_string_literal: true

module CursorPagination
  # Positions a scope on a cursor. The sort of a cursor runs in a single direction, so a
  # single row-value comparison bounds the page and an index on the tuple serves it (read
  # backward for an ascending sort on a descending index).
  module Keyset
    # Must be the last scope operation of a query: `reorder` drops any ordering applied
    # before it, and a later `order` would be appended after the tuple.
    def self.apply(scope, cursor)
      if scope.table_name != cursor.table
        raise ArgumentError, "cursor minted for #{cursor.table} applied to #{scope.table_name}"
      end

      sort = cursor.sort
      scope = case cursor.direction
      when :forward
        scope.where("#{row(scope, sort)} #{operator(sort, :forward)} (?, ?)", *bound_key(cursor.key))
      when :backward
        scope.where("#{row(scope, sort)} #{operator(sort, :backward)} (?, ?)", *bound_key(cursor.key))
      else
        scope
      end

      # One extra row tells whether the list continues in the direction being paged.
      scope.reorder(order(cursor)).limit(cursor.limit + 1)
    end

    # The order the page is read in. Paging backward walks towards the start of the list,
    # so the rows closest to the anchor come first; `Page` restores the list order.
    def self.order(cursor)
      cursor.backward? ? reversed(cursor.sort) : cursor.sort
    end

    # Binds a Time/DateTime from the cursor key as a microsecond-precision UTC literal,
    # which both ClickHouse DateTime64(3) and Postgres timestamptz parse. Passing the raw
    # Time through the ClickHouse adapter's `quoted_date` truncates it to the whole second
    # (`value.to_fs(:db)`), dropping rows that share the anchor's second. The string
    # tiebreak is bound unchanged.
    def self.bound_key(key)
      key.map do |value|
        (value.is_a?(Time) || value.is_a?(DateTime)) ? value.utc.strftime("%Y-%m-%d %H:%M:%S.%6N") : value
      end
    end
    private_class_method :bound_key

    def self.row(scope, sort)
      columns = sort.keys.map { |column| "#{scope.quoted_table_name}.#{scope.connection.quote_column_name(column)}" }
      "(#{columns.join(", ")})"
    end
    private_class_method :row

    # The rows past the anchor, in the direction being paged: lower values when walking
    # forward a descending sort, higher ones when walking it backward, and the other way
    # around for an ascending sort.
    def self.operator(sort, direction)
      descending = sort.values.first == :desc
      (descending == (direction == :forward)) ? "<" : ">"
    end
    private_class_method :operator

    def self.reversed(sort)
      sort.transform_values { (it == :desc) ? :asc : :desc }
    end
    private_class_method :reversed
  end
end
