# frozen_string_literal: true

module Events
  module Stores
    module Clickhouse
      module DedupStrategies
        # Baseline: one argMax call per deduplicated column, each picking the value
        # associated with the latest enriched_at within the dedup key group.
        class ArgMaxStrategy < BaseStrategy
          def name
            "A argMax"
          end

          def sql
            <<~SQL.squish
              SELECT
                #{GROUP_COLUMNS.join(", ")},
                #{arg_max_columns_sql}
              FROM events_enriched
              WHERE #{sanitized_key_filters}
              GROUP BY #{GROUP_COLUMNS.join(", ")}
            SQL
          end

          private

          def arg_max_columns_sql
            DEDUPLICATED_COLUMNS
              .map { |c| "argMax(#{c}, enriched_at) AS #{c}" }
              .join(", ")
          end
        end
      end
    end
  end
end
