# frozen_string_literal: true

module CursorPagination
  # Total of an unpaginated relation, for the first page of a cursor-paginated list.
  #
  # Exact below the cap. Beyond it, or when the count times out, it falls back to the
  # planner's row estimate, flagged as estimated. The estimate alone is unreliable with
  # correlated filters and between two `ANALYZE`, hence only used where precision
  # matters least, and never reported below the cap once the cap is reached.
  class TotalCount
    MAX_COUNTED_RECORDS = 10_000
    DEFAULT_TIMEOUT_MS = 2_000

    # `outcome` tells why a total is estimated: the cap was reached, or the count timed out.
    Result = Data.define(:value, :outcome) do
      def estimated
        outcome != :exact
      end
    end

    def self.call(relation)
      new(relation).call
    end

    def initialize(relation)
      @relation = relation.except(:order, :limit, :offset, :includes, :preload, :eager_load)
    end

    def call
      result = count
      Yabeda.api_pagination.total_counts_total.increment({table: relation.table_name, outcome: result.outcome})
      result
    end

    private

    attr_reader :relation

    def count
      counted = capped_count

      if counted <= MAX_COUNTED_RECORDS
        Result.new(value: counted, outcome: :exact)
      else
        Result.new(value: [planner_estimate, counted].max, outcome: :capped)
      end
    rescue ActiveRecord::QueryCanceled
      Result.new(value: planner_estimate, outcome: :timed_out)
    end

    # Counts one past the cap, so that a list landing exactly on it is reported exactly.
    def capped_count
      relation.transaction(requires_new: true) do
        restrict_statement_timeout
        relation.limit(MAX_COUNTED_RECORDS + 1).count
      end
    end

    # Lowers the statement timeout for the transaction wrapping the count (`set_config`
    # with `is_local` is `SET LOCAL`), but never raises it: a stricter timeout configured
    # for the connection keeps applying. `pg_settings` reports it in milliseconds, 0
    # meaning none.
    def restrict_statement_timeout
      relation.connection.select_value(ActiveRecord::Base.sanitize_sql_array([<<~SQL, timeout_ms, timeout_ms]))
        SELECT set_config(
          'statement_timeout',
          (CASE WHEN setting::bigint = 0 THEN ? ELSE LEAST(setting::bigint, ?) END)::text,
          true
        )
        FROM pg_settings
        WHERE name = 'statement_timeout'
      SQL
    end

    def planner_estimate
      plan = relation.connection.select_value("EXPLAIN (FORMAT JSON) #{relation.to_sql}")
      plan = JSON.parse(plan) if plan.is_a?(String)
      plan.dig(0, "Plan", "Plan Rows").to_i
    end

    def timeout_ms
      timeout = ENV["LAGO_API_TOTAL_COUNT_TIMEOUT_MS"].to_i
      timeout.positive? ? timeout : DEFAULT_TIMEOUT_MS
    end
  end
end
