# frozen_string_literal: true

module CursorPagination
  # Positions a scope on a cursor: keeps the rows past the anchor, in the order of the sort.
  module Keyset
    # Must be the last scope operation of a query: `reorder` drops any ordering applied
    # before it, and a later `order` would be appended after the tuple.
    def self.apply(scope, cursor)
      if scope.table_name != cursor.table
        raise ArgumentError, "cursor minted for #{cursor.table} applied to #{scope.table_name}"
      end

      scope = scope.where(*past_anchor(scope, cursor)) unless cursor.direction == :first

      # One extra row tells whether the list continues in the direction being paged.
      scope.reorder(order(cursor)).limit(cursor.limit + 1)
    end

    # The order the page is read in. Paging backward walks towards the start of the list,
    # so the rows closest to the anchor come first; `Page` restores the list order.
    def self.order(cursor)
      cursor.backward? ? reversed(cursor.sort) : cursor.sort
    end

    # The condition, with its values, that keeps the rows past the anchor.
    def self.past_anchor(scope, cursor)
      columns = cursor.sort.keys.map { "#{scope.quoted_table_name}.#{scope.connection.quote_column_name(it)}" }
      operators = cursor.sort.values.map { operator(it, cursor.direction) }
      key = bound_key(cursor.key)

      if operators.uniq.one?
        row_comparison(columns, operators.first, key)
      else
        column_by_column(columns, operators, key)
      end
    end
    private_class_method :past_anchor

    # A time binds as a microsecond UTC literal, which both Postgres and ClickHouse parse: the
    # ClickHouse adapter would quote a `Time` to the whole second, dropping the rows that share
    # the anchor's second.
    def self.bound_key(key)
      key.map { it.is_a?(Time) ? it.utc.strftime("%Y-%m-%d %H:%M:%S.%6N") : it }
    end
    private_class_method :bound_key

    # Every column runs in the same direction: `(a, b) < (x, y)`, which an index on the
    # tuple serves (read backward for an ascending sort on a descending index).
    def self.row_comparison(columns, operator, key)
      ["(#{columns.join(", ")}) #{operator} (#{columns.map { "?" }.join(", ")})", *key]
    end
    private_class_method :row_comparison

    # The columns run in different directions, which one row comparison cannot express. A
    # row is past the anchor on its first column, or ties on it and is past it on the next:
    #
    #   a < x OR (a = x AND b < y) OR (a = x AND b = y AND c > z)
    #
    # `a <= x` comes first: the OR implies it, and it gives an index on the tuple a place to
    # start, where the OR alone would filter the whole list.
    def self.column_by_column(columns, operators, key)
      branches = columns.each_index.map do |position|
        ties = columns.first(position).map { "#{it} = ?" }
        "(#{[*ties, "#{columns[position]} #{operators[position]} ?"].join(" AND ")})"
      end
      branch_values = columns.each_index.flat_map { key.first(it + 1) }

      ["#{columns.first} #{operators.first}= ? AND (#{branches.join(" OR ")})", key.first, *branch_values]
    end
    private_class_method :column_by_column

    # Past the anchor means lower values when paging a descending column forward, or an
    # ascending one backward, and higher values otherwise.
    def self.operator(direction, paging)
      ((direction == :desc) == (paging == :forward)) ? "<" : ">"
    end
    private_class_method :operator

    def self.reversed(sort)
      sort.transform_values { (it == :desc) ? :asc : :desc }
    end
    private_class_method :reversed
  end
end
