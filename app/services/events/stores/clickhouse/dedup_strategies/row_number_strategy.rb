# frozen_string_literal: true

module Events
  module Stores
    module Clickhouse
      module DedupStrategies
        class RowNumberStrategy < BaseStrategy
          def name
            "C row_number"
          end

          def sql
            <<~SQL.squish
              SELECT
                #{BaseStrategy::SELECT_COLUMNS.join(", ")}
              FROM (
                SELECT
                  #{BaseStrategy::SELECT_COLUMNS.join(", ")},
                  row_number() OVER (
                    PARTITION BY #{GROUP_COLUMNS.join(", ")}
                    ORDER BY enriched_at DESC
                  ) AS rn
                FROM events_enriched
                WHERE #{sanitized_key_filters}
              )
              WHERE rn = 1
            SQL
          end
        end
      end
    end
  end
end
