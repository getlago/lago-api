# frozen_string_literal: true

module Events
  module Stores
    module Clickhouse
      class CleanDuplicatedEnrichedExpandedService < BaseService
        Result = BaseResult[:removed_count]

        def initialize(subscription:, codes: [])
          @subscription = subscription
          @codes = codes
          super
        end

        def call
          result.removed_count = count_duplicates
          return result if result.removed_count.zero?

          delete_duplicated_events

          result
        end

        def count_duplicates
          duplicated_events.size
        end

        private

        attr_reader :subscription, :codes

        def duplicated_events
          sql = ActiveRecord::Base.sanitize_sql_for_conditions([
            duplicates_subquery,
            sql_params
          ])

          result = Events::Stores::Utils::ClickhouseConnection.connection_with_retry do |conn|
            conn.select_all(sql)
          end
          result.to_a
        end

        def delete_duplicated_events
          return if result.removed_count.zero?

          sql = ActiveRecord::Base.sanitize_sql_for_conditions(
            [
              <<~SQL,
                DELETE FROM events_enriched_expanded
                WHERE
                  #{base_conditions}
                  AND (transaction_id, timestamp, charge_id, charge_filter_id) IN (#{duplicates_subquery})
                  AND (transaction_id, timestamp, charge_id, charge_filter_id, enriched_at) NOT IN (
                    SELECT transaction_id, timestamp, charge_id, charge_filter_id, max(enriched_at)
                    FROM events_enriched_expanded
                    WHERE
                      #{base_conditions}
                      AND (transaction_id, timestamp, charge_id, charge_filter_id) IN (#{duplicates_subquery})
                    GROUP BY transaction_id, timestamp, charge_id, charge_filter_id
                  )
                SETTINGS mutations_sync = 1
              SQL
              sql_params
            ]
          )

          Events::Stores::Utils::ClickhouseConnection.connection_with_retry do |conn|
            conn.execute(sql)
          end
        end

        def base_conditions
          conditions = <<~SQL.squish
            organization_id = :organization_id
            AND subscription_id = :subscription_id
            AND timestamp >= :started_at
          SQL
          conditions += " AND code IN (:codes)" if codes.present?
          conditions
        end

        def duplicates_subquery
          <<~SQL.squish
            SELECT transaction_id, timestamp, charge_id, charge_filter_id
            FROM events_enriched_expanded
            WHERE #{base_conditions}
            GROUP BY transaction_id, timestamp, charge_id, charge_filter_id
            HAVING count() > 1
          SQL
        end

        def sql_params
          {
            organization_id: subscription.organization_id,
            subscription_id: subscription.id,
            started_at: subscription.started_at,
            codes: codes
          }
        end
      end
    end
  end
end
