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
          duplicated_count = count_duplicates
          remove_duplicated_events
          result.removed_count = duplicated_count - count_duplicates

          result
        end

        def count_duplicates
          duplicated_events.size
        end

        private

        attr_reader :subscription, :codes

        delegate :organization, to: :subscription

        def connection
          @connection ||= ::Clickhouse::EventsEnrichedExpanded.connection
        end

        def where_clause
          conditions = [
            "organization_id = #{connection.quote(organization.id)}",
            "subscription_id = #{connection.quote(subscription.id)}",
            "timestamp >= #{connection.quote(subscription.started_at.strftime("%Y-%m-%d %H:%M:%S"))}"
          ]

          if codes.present?
            code_list = codes.map { |c| connection.quote(c) }.join(", ")
            conditions << "code IN (#{code_list})"
          end

          conditions.join(" AND ")
        end

        def base_scope
          scope = ::Clickhouse::EventsEnrichedExpanded
            .where(organization_id: organization.id)
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

        def remove_duplicated_events
          duplicates = duplicated_events.to_a
          return if duplicates.empty?

          duplicates.each do |transaction_id, event_timestamp, charge_id, charge_filter_id|
            # Fetch all enriched_at timestamps for the duplicated events
            enriched_at = base_scope
              .where(timestamp: event_timestamp)
              .where(transaction_id: transaction_id)
              .where(charge_id: charge_id)
              .where(charge_filter_id: charge_filter_id)
              .order(enriched_at: :desc)
              .pluck(:enriched_at)

            base_scope
              .where(timestamp: event_timestamp)
              .where(transaction_id: transaction_id)
              .where(charge_id: charge_id)
              .where(charge_filter_id: charge_filter_id)
              .where(enriched_at: enriched_at[1..])
              .delete_all
          end
        end
      end
    end
  end
end
