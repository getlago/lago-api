# frozen_string_literal: true

module Events
  module Stores
    module Clickhouse
      # Attributed usage of one tree level: one row per attribution value, ranked, with the totals of
      # the whole level.
      #
      # Each event is priced on its own row: the charge's price lookup resolves the rank of the filter
      # pricing it, and the rank picks the unit amount. The rows are then grouped by the attribution
      # value only, into a fixed set of cells (units, amount, events) per charge, so the number of
      # filters never adds groups. A split charge gets one cell per filter, plus the default one.
      #
      # Ranking and level totals are window functions over every group, computed before paging. The
      # unattributed usage (empty value) is ranked in its own partition, and the query returns it
      # along with the page and the first ranked row, which always carries the level totals.
      class AttributedUsageQuery
        include Events::Stores::Utils::ClickhouseSqlHelpers

        ChargeColumn = Data.define(:charge_id, :code, :count, :unit_amount_cents, :lookup, :split)
        Cell = Data.define(:charge_id, :charge_filter_id, :priced, :column_index, :rank)

        SCALE = 12
        ORDERS = {"amount" => "amount", "events_count" => "events"}.freeze

        def initialize(organization_id:, external_subscription_id:, from_datetime:, to_datetime:, group_key:, label_filters:,
          charge_columns:, order_by:, search:, limit:, offset:, deduplicate:, max_groups:, max_execution_time:)
          @organization_id = organization_id
          @external_subscription_id = external_subscription_id
          @from_datetime = from_datetime
          @to_datetime = to_datetime
          @group_key = group_key
          @label_filters = label_filters
          @charge_columns = charge_columns
          @order_by = order_by
          @search = search
          @limit = limit
          @offset = offset
          @deduplicate = deduplicate
          @max_groups = max_groups
          @max_execution_time = max_execution_time
        end

        def cells
          @cells ||= charge_columns.each_with_index.flat_map do |column, index|
            priced = !column.unit_amount_cents.nil?

            if column.split
              column.lookup.filter_ids.map.with_index(1) { |filter_id, rank| Cell.new(column.charge_id, filter_id, priced, index, rank) } +
                [Cell.new(column.charge_id, nil, priced, index, default_rank(column))]
            else
              [Cell.new(column.charge_id, nil, priced, index, nil)]
            end
          end
        end

        def rows
          ::Clickhouse::BaseRecord.with_connection do |connection|
            connection.with_settings(**Events::Stores::Utils::ClickhouseConnection::QUERY_SETTINGS) do
              connection.select_all(query).to_a
            end
          end
        end

        def query
          <<~SQL.squish
            SELECT
              node, rank, in_page, groups_count,
              amount, events, #{cell_names.join(", ")},
              total_amount, total_events, #{cell_names.map { "total_#{it}" }.join(", ")}
            FROM (
              SELECT *, #{page_condition_sql} AS in_page
              FROM (
                SELECT *,
                  row_number() OVER ranked AS rank,
                  count() OVER level AS groups_count,
                  #{search_rank_sql}
                  #{level_windows_sql}
                FROM (
                  SELECT
                    node,
                    #{cells_sql.join(", ")},
                    #{amount_sql} AS amount,
                    count() AS events
                  FROM (
                    SELECT #{event_columns_sql.join(", ")}
                    FROM events_enriched#{" FINAL" if deduplicate}
                    WHERE #{where_sql}
                  )
                  GROUP BY node
                )
                WINDOW
                  level AS (PARTITION BY node = ''),
                  ranked AS (PARTITION BY node = '' ORDER BY #{ORDERS.fetch(order_by)} DESC, node ASC ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW)
              )
            )
            WHERE node = '' OR rank = 1 OR in_page
            ORDER BY node = '' ASC, rank ASC
            SETTINGS
              max_rows_to_group_by = #{Integer(max_groups)},
              group_by_overflow_mode = 'throw',
              max_execution_time = #{Integer(max_execution_time)},
              timeout_overflow_mode = 'throw'
          SQL
        end

        private

        attr_reader :organization_id, :external_subscription_id, :from_datetime, :to_datetime, :group_key, :label_filters,
          :charge_columns, :order_by, :search, :limit, :offset, :deduplicate, :max_groups, :max_execution_time

        def cell_names
          @cell_names ||= cells.each_index.flat_map { ["units_#{it}", "amount_#{it}", "events_#{it}"] }
        end

        def event_columns_sql
          columns = [
            "#{sql_condition("attribution_labels[?]", group_key)} AS node",
            "code",
            "toDecimal128(coalesce(decimal_value, 0), #{SCALE}) AS event_units"
          ]

          charge_columns.each_with_index do |column, index|
            columns << "if(#{code_condition(column)}, #{rank_sql(column)}, 0) AS rank_#{index}" if column.lookup
            columns << "#{price_sql(column, index)} AS price_#{index}" if column.unit_amount_cents
          end

          columns
        end

        # The best filter is the lowest rank found across the key sets; each lookup misses with the
        # default rank, which the prices array maps to the charge's own price.
        def rank_sql(column)
          lookups = column.lookup.key_sets.map do |keys, entries|
            values_sql = (keys.size == 1) ? property_sql(keys.first) : "concat(#{keys.map { property_sql(it) }.join(", char(31), ")})"

            "transform(#{values_sql}, [#{entries.keys.map { quote(it) }.join(", ")}], " \
              "CAST([#{entries.values.join(", ")}], 'Array(UInt32)'), toUInt32(#{default_rank(column)}))"
          end

          case lookups.size
          when 0 then "toUInt32(#{default_rank(column)})"
          when 1 then lookups.first
          else "least(#{lookups.join(", ")})"
          end
        end

        def price_sql(column, index)
          return decimal_sql(column.unit_amount_cents) unless column.lookup

          prices = (column.lookup.unit_amounts_cents + [column.unit_amount_cents]).map { quote(decimal_literal(it)) }
          "arrayElement(arrayMap(x -> toDecimal128(x, #{SCALE}), [#{prices.join(", ")}]), rank_#{index})"
        end

        def cells_sql
          cells.each_with_index.flat_map do |cell, index|
            column = charge_columns[cell.column_index]
            condition = code_condition(column)
            condition += " AND rank_#{cell.column_index} = #{cell.rank}" if cell.rank
            units = column.count ? "toDecimal128(1, #{SCALE})" : "event_units"
            amount = if cell.priced
              "sumIf(toDecimal128(#{units} * price_#{cell.column_index}, #{SCALE}), #{condition})"
            else
              decimal_sql(0)
            end

            ["sumIf(#{units}, #{condition}) AS units_#{index}", "#{amount} AS amount_#{index}", "countIf(#{condition}) AS events_#{index}"]
          end
        end

        def amount_sql
          priced = cells.each_index.select { cells[it].priced }
          priced.any? ? priced.map { "amount_#{it}" }.join(" + ") : decimal_sql(0)
        end

        def level_windows_sql
          %w[amount events].concat(cell_names).map { |name| "sum(#{name}) OVER level AS total_#{name}" }.join(", ")
        end

        def search_rank_sql
          return "" unless search

          "sum(#{search_match_sql}) OVER ranked AS search_rank,"
        end

        def page_condition_sql
          first = Integer(offset) + 1
          last = Integer(offset) + Integer(limit)

          if search
            "node != '' AND #{search_match_sql} AND search_rank BETWEEN #{first} AND #{last}"
          else
            "node != '' AND rank BETWEEN #{first} AND #{last}"
          end
        end

        def search_match_sql
          sql_condition("positionCaseInsensitiveUTF8(node, ?) > 0", search)
        end

        def where_sql
          conditions = [
            sql_condition(
              "organization_id = ? AND external_subscription_id = ? AND code IN (?)",
              organization_id,
              external_subscription_id,
              charge_columns.map(&:code).uniq
            ),
            sql_condition("timestamp >= ? AND timestamp <= ?", from_datetime, to_datetime)
          ]

          label_filters.each do |key, values|
            conditions << sql_condition("attribution_labels[?] IN (?)", key, values)
          end

          conditions.join(" AND ")
        end

        def code_condition(column)
          sql_condition("code = ?", column.code)
        end

        def property_sql(key)
          sql_condition("properties[?]", key.to_s)
        end

        def decimal_sql(value)
          "toDecimal128(#{quote(decimal_literal(value))}, #{SCALE})"
        end

        def default_rank(column)
          column.lookup.filter_ids.size + 1
        end
      end
    end
  end
end
