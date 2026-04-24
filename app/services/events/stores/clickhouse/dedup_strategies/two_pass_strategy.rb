# frozen_string_literal: true

module Events
  module Stores
    module Clickhouse
      module DedupStrategies
        # First pass (latest_enriched CTE) finds the max(enriched_at) per dedup key using
        # only key columns (no properties Map). Second pass reads events_enriched for the
        # surviving (keys + enriched_at) tuples and collapses enriched_at ties via `any()`
        # with a GROUP BY on the dedup key to ensure exactly one row per dedup key.
        class TwoPassStrategy < BaseStrategy
          AGGREGATED_COLUMNS = (SELECT_COLUMNS - GROUP_COLUMNS).freeze

          def name
            "D two-pass"
          end

          def sql
            <<~SQL.squish
              WITH latest_enriched AS (
                SELECT
                  #{GROUP_COLUMNS.join(", ")},
                  max(enriched_at) AS max_enriched_at
                FROM events_enriched
                WHERE #{sanitized_key_filters}
                GROUP BY #{GROUP_COLUMNS.join(", ")}
              )
              SELECT
                #{select_columns_sql}
              FROM events_enriched AS e
              INNER JOIN latest_enriched AS l
                ON #{GROUP_COLUMNS.map { |c| "e.#{c} = l.#{c}" }.join(" AND ")}
               AND e.enriched_at = l.max_enriched_at
              WHERE #{sanitized_key_filters(alias_prefix: "e")}
              GROUP BY #{GROUP_COLUMNS.map { |c| "e.#{c}" }.join(", ")}
            SQL
          end

          private

          def select_columns_sql
            (
              GROUP_COLUMNS.map { |c| "e.#{c}" } +
              AGGREGATED_COLUMNS.map { |c| "any(e.#{c}) AS #{c}" }
            ).join(", ")
          end
        end
      end
    end
  end
end
