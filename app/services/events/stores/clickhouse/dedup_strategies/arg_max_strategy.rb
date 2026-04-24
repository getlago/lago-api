# frozen_string_literal: true

module Events
  module Stores
    module Clickhouse
      module DedupStrategies
        # Baseline: the current implementation in ClickhouseStore#deduplicated_events_sql,
        # wrapped so the benchmark measures the exact code path used in production.
        class ArgMaxStrategy < BaseStrategy
          def name
            "A argMax"
          end

          def sql
            store = Events::Stores::ClickhouseStore.new(
              subscription: subscription,
              boundaries: boundaries,
              code: code,
              deduplicate: true
            )

            store.deduplicated_events_sql(
              from_datetime: from_datetime,
              to_datetime: to_datetime,
              deduplicated_columns: DEDUPLICATED_COLUMNS.dup
            ).to_sql
          end
        end
      end
    end
  end
end
