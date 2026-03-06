# frozen_string_literal: true

module Events
  module Stores
    module Clickhouse
      class CleanDuplicatedEnrichedExpandedService < BaseService
        Result = BaseResult[:removed_count]

        def initialize(subscription:, codes: [], async: true)
          @subscription = subscription
          @codes = codes
          @async = async
          super
        end

        def call
          duplicated_count = count_duplicates
          remove_duplicated_events
          result.removed_count = duplicated_count

          result
        end

        def count_duplicates
          duplicated_events.size
        end

        private

        attr_reader :subscription, :codes, :async

        def base_scope
          scope = ::Clickhouse::EventsEnrichedExpanded
            .where(organization_id: subscription.organization_id)
            .where(subscription_id: subscription.id)

          if codes.present?
            scope = scope.where(code: codes)
          end

          scope
        end

        def duplicated_events
          base_scope
            .where(timestamp: subscription.started_at..)
            .group(:transaction_id, :timestamp, :charge_id, :charge_filter_id)
            .having("count() > 1")
            .pluck(:transaction_id, :timestamp, :charge_id, :charge_filter_id)
        end

        def connection
          @connection ||= ::Clickhouse::EventsEnrichedExpanded.connection
        end

        def remove_duplicated_events
          duplicates = duplicated_events.to_a
          return if duplicates.empty?

          code_condition = ""
          if codes.present?
            code_condition = "AND code IN (#{codes.map { connection.quote(it) }.join(", ")})"
          end

          sql = <<~SQL
            ALTER TABLE events_enriched_expanded
            DELETE WHERE (transaction_id, timestamp, charge_id, charge_filter_id, enriched_at) IN (
              SELECT
                transaction_id,
                timestamp,
                charge_id,
                charge_filter_id,
                enriched_at
              FROM (
                SELECT
                  transaction_id,
                  timestamp,
                  charge_id,
                  charge_filter_id,
                  enriched_at,
                  row_number() OVER (
                    PARTITION BY transaction_id, timestamp, charge_id, charge_filter_id
                    ORDER BY enriched_at DESC
                  ) AS row_n
                FROM events_enriched_expanded
                WHERE
                  organization_id = :organization_id AND
                  subscription_id = :subscription_id AND
                  timestamp >= :timestamp
                  #{code_condition}
              )
              WHERE row_n > 1
            )
          SQL

          sql += " SETTINGS mutations_sync = 1" unless async

          query = ActiveRecord::Base.sanitize_sql_for_conditions(
            [
              sql,
              {
                organization_id: subscription.organization_id,
                subscription_id: subscription.id,
                timestamp: subscription.started_at
              }
            ]
          )

          connection.execute(query)
        end
      end
    end
  end
end
