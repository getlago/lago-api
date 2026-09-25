# frozen_string_literal: true

module Events
  module Stores
    module Clickhouse
      class AttributedUsageQuery
        include Events::Stores::Utils::ClickhouseSqlHelpers

        ChargeColumn = Data.define(:charge_id, :code, :count, :priced, :split, :buckets)
        PricingBucket = Data.define(:charge_filter_id, :matching_filters, :ignored_filters, :unit_amount_cents)

        UNITS_SCALE = 26
        PRICE_SCALE = 20
        AMOUNT_SCALE = UNITS_SCALE + PRICE_SCALE
        SPLIT_SEPARATOR = "|"

        def initialize(organization_id:, external_subscription_id:, from_datetime:, to_datetime:, group_key:, label_filters:,
          charge_columns:, limit:, offset:, deduplicate:, max_groups:, max_execution_time:)
          @organization_id = organization_id
          @external_subscription_id = external_subscription_id
          @from_datetime = from_datetime
          @to_datetime = to_datetime
          @group_key = group_key
          @label_filters = label_filters
          @charge_columns = charge_columns
          @limit = limit
          @offset = offset
          @deduplicate = deduplicate
          @max_groups = max_groups
          @max_execution_time = max_execution_time
        end

        def query
          <<~SQL.squish
            SELECT
              node,
              columns,
              amount_cents,
              events_count,
              sum(amount_cents) OVER () AS total_amount_cents,
              sum(events_count) OVER () AS total_events_count,
              count() OVER () AS groups_count
            FROM (
              SELECT
                node,
                sumMap(column_keys, column_units, column_amounts, column_counts) AS columns,
                sum(arraySum(column_amounts)) AS amount_cents,
                count() AS events_count
              FROM (
                SELECT
                  #{sql_condition("attribution_labels[?]", group_key)} AS node,
                  #{per_code_array_sql(&method(:key_sql))} AS column_keys,
                  #{per_code_array_sql(&method(:units_sql))} AS column_units,
                  #{per_code_array_sql(&method(:amount_sql))} AS column_amounts,
                  #{per_code_array_sql { "toUInt64(1)" }} AS column_counts
                FROM events_enriched#{" FINAL" if deduplicate}
                WHERE #{where_sql}
              )
              GROUP BY node
            )
            ORDER BY node = '' DESC, amount_cents DESC, events_count DESC, node ASC
            LIMIT #{Integer(limit)} OFFSET #{Integer(offset)}
            SETTINGS
              max_rows_to_group_by = #{Integer(max_groups)},
              group_by_overflow_mode = 'throw',
              max_execution_time = #{Integer(max_execution_time)}
          SQL
        end

        def self.column_key(charge_id:, charge_filter_id: nil)
          [charge_id, charge_filter_id].join(SPLIT_SEPARATOR)
        end

        def self.parse_column_key(key)
          charge_id, charge_filter_id = key.split(SPLIT_SEPARATOR, 2)
          [charge_id, charge_filter_id.presence]
        end

        private

        attr_reader :organization_id, :external_subscription_id, :from_datetime, :to_datetime, :group_key, :label_filters,
          :charge_columns, :limit, :offset, :deduplicate, :max_groups, :max_execution_time

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

        def per_code_array_sql(&)
          branches = charge_columns.group_by(&:code).flat_map do |code, columns|
            [sql_condition("code = ?", code), "[#{columns.map(&).join(", ")}]"]
          end

          "multiIf(#{branches.join(", ")}, [])"
        end

        def key_sql(column)
          return quote(self.class.column_key(charge_id: column.charge_id)) unless column.split

          bucket_sql(column) do |bucket|
            quote(self.class.column_key(charge_id: column.charge_id, charge_filter_id: bucket.charge_filter_id))
          end
        end

        def units_sql(column)
          return "toDecimal128(1, #{UNITS_SCALE})" if column.count

          "coalesce(decimal_value, toDecimal128(0, #{UNITS_SCALE}))"
        end

        def amount_sql(column)
          return "toDecimal256(0, #{AMOUNT_SCALE})" unless column.priced

          unit_amount = bucket_sql(column) do |bucket|
            "toDecimal256('#{decimal_literal(bucket.unit_amount_cents)}', #{PRICE_SCALE})"
          end

          "toDecimal256(#{units_sql(column)}, #{UNITS_SCALE}) * #{unit_amount}"
        end

        def bucket_sql(column)
          default_bucket = column.buckets.find { it.charge_filter_id.nil? }
          filter_buckets = column.buckets - [default_bucket]
          return yield(default_bucket) if filter_buckets.empty?

          branches = filter_buckets.flat_map { [filter_condition_sql(it), yield(it)] }
          "multiIf(#{branches.join(", ")}, #{yield(default_bucket)})"
        end

        def filter_condition_sql(bucket)
          conditions = bucket.matching_filters.map do |key, values|
            sql_condition("properties[?] IN (?)", key.to_s, values.map(&:to_s))
          end

          ignored = bucket.ignored_filters.filter_map do |ignored_filter|
            clause = ignored_filter.filter_map do |key, values|
              next if values.empty?

              sql_condition("coalesce(properties[?], '') IN (?)", key.to_s, values.map(&:to_s))
            end

            "(#{clause.join(" AND ")})" if clause.any?
          end
          conditions << "NOT (#{ignored.join(" OR ")})" if ignored.any?

          conditions.any? ? "(#{conditions.join(" AND ")})" : "1"
        end
      end
    end
  end
end
