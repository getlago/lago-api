# frozen_string_literal: true

module Events
  module Stores
    module Clickhouse
      module DedupStrategies
        # Folds the four per-column argMax calls into a single argMax over a tuple.
        # ClickHouse maintains one running winner per group instead of four.
        class ArgMaxTupleStrategy < BaseStrategy
          def name
            "B argMax tuple"
          end

          def sql
            <<~SQL.squish
              SELECT
                code,
                organization_id,
                external_subscription_id,
                transaction_id,
                timestamp,
                tupleElement(latest, 1) AS value,
                tupleElement(latest, 2) AS decimal_value,
                tupleElement(latest, 3) AS properties,
                tupleElement(latest, 4) AS precise_total_amount_cents
              FROM (
                SELECT
                  code,
                  organization_id,
                  external_subscription_id,
                  transaction_id,
                  timestamp,
                  argMax(
                    (value, decimal_value, properties, precise_total_amount_cents),
                    enriched_at
                  ) AS latest
                FROM events_enriched
                WHERE #{sanitized_key_filters}
                GROUP BY #{GROUP_COLUMNS.join(", ")}
              )
            SQL
          end
        end
      end
    end
  end
end
