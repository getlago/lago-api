# frozen_string_literal: true

module Events
  module Stores
    module Clickhouse
      # This services cleans the duplicated events_enriched_expanded records that might have been created by
      # the execution of the events:reprocess rake task.
      # By default, the service removes the records asynchronously relying on the `ALTER TABLE DELETE`
      # mutation mechanism of Clickhouse.
      # The remove can be made synchronously by setting `async: false`, but depending on the number of
      # records, this may be slow and lead to timeout errors.
      #
      # The removal process can be monitored on Clickhouse by running the following query:
      #   SELECT
      #     database,
      #     table,
      #     mutation_id,
      #     command,
      #     create_time,
      #     is_done,
      #     parts_to_do,
      #     latest_fail_reason
      #   FROM system.mutations
      #   WHERE table = 'events_enriched_expanded'
      #     AND is_done = 0
      #   ORDER BY create_time DESC
      class CleanDuplicatedEnrichedExpandedService < BaseService
        Result = BaseResult[:duplicated_count]

        BATCH_SIZE = 500

        def initialize(subscription:, codes: [], async: true)
          @subscription = subscription
          @codes = codes
          @async = async

          super
        end

        def call
          result.duplicated_count = count_duplicates
          return result if result.duplicated_count.zero?

          delete_duplicated_events

          result
        end

        def count_duplicates
          sql = ActiveRecord::Base.sanitize_sql_for_conditions([
            <<~SQL.squish,
              SELECT count() AS duplicated_count FROM (#{duplicates_subquery})
            SQL
            sql_params
          ])

          row = Events::Stores::Utils::ClickhouseConnection.connection_with_retry do |connection|
            connection.select_one(sql)
          end
          row["duplicated_count"].to_i
        end

        private

        attr_reader :subscription, :codes, :async

        def quote(value)
          ::Clickhouse::BaseRecord.connection.quote(value)
        end

        def fetch_duplicated_batch(offset)
          sql = ActiveRecord::Base.sanitize_sql_for_conditions([
            "#{duplicates_subquery} LIMIT #{BATCH_SIZE} OFFSET #{offset}",
            sql_params
          ])

          result = Events::Stores::Utils::ClickhouseConnection.connection_with_retry do |conn|
            conn.select_all(sql)
          end
          result.to_a
        end

        def delete_duplicated_events
          offset = 0

          loop do
            batch = fetch_duplicated_batch(offset)
            break if batch.empty?

            dupes_list = batch.map do |row|
              "(#{quote(row["transaction_id"])}, #{quote(row["timestamp"])}, #{quote(row["charge_id"])}, #{quote(row["charge_filter_id"])})"
            end.join(", ")

            keep_list = batch.map do |row|
              "(#{quote(row["transaction_id"])}, #{quote(row["timestamp"])}, #{quote(row["charge_id"])}, #{quote(row["charge_filter_id"])}, #{quote(row["max_enriched_at"])})"
            end.join(", ")

            sql = ActiveRecord::Base.sanitize_sql_for_conditions(
              [
                <<~SQL,
                  ALTER TABLE events_enriched_expanded
                  DELETE WHERE
                    #{base_conditions}
                    AND (transaction_id, timestamp, charge_id, charge_filter_id) IN (#{dupes_list})
                    AND (transaction_id, timestamp, charge_id, charge_filter_id, enriched_at) NOT IN (#{keep_list})

                    #{"SETTINGS mutations_sync = 1" unless async}
                SQL
                sql_params
              ]
            )

            Events::Stores::Utils::ClickhouseConnection.connection_with_retry do |conn|
              conn.execute(sql)
            end

            offset += BATCH_SIZE
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
            SELECT transaction_id, timestamp, charge_id, charge_filter_id, max(enriched_at) AS max_enriched_at
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
1
