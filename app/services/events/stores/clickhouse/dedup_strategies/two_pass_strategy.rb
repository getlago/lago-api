# frozen_string_literal: true

module Events
  module Stores
    module Clickhouse
      module DedupStrategies
        # First pass finds the max(enriched_at) per dedup key using only key columns
        # (no properties Map). Second pass reads events_enriched for the surviving
        # (keys + enriched_at) tuples.
        class TwoPassStrategy < BaseStrategy
          def name
            "D two-pass"
          end

          def sql
            <<~SQL.squish
              WITH latest AS (
                SELECT
                  #{GROUP_COLUMNS.join(", ")},
                  max(enriched_at) AS max_enriched_at
                FROM events_enriched
                WHERE #{sanitized_key_filters}
                GROUP BY #{GROUP_COLUMNS.join(", ")}
              )
              SELECT
                #{BaseStrategy::SELECT_COLUMNS.map { |c| "e.#{c}" }.join(", ")}
              FROM events_enriched AS e
              INNER JOIN latest AS l
                ON #{GROUP_COLUMNS.map { |c| "e.#{c} = l.#{c}" }.join(" AND ")}
               AND e.enriched_at = l.max_enriched_at
              WHERE #{sanitized_key_filters(alias_prefix: "e")}
            SQL
          end
        end
      end
    end
  end
end
