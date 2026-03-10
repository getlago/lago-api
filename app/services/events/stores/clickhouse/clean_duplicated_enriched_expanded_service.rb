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
          result.removed_count = duplicated_count

          result
        end

        def count_duplicates
          duplicated_events.size
        end

        private

        attr_reader :subscription, :codes

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
            .pluck(:transaction_id, :timestamp, :charge_id, :charge_filter_id, Arel.sql("max(enriched_at)"))
        end

        def remove_duplicated_events
          duplicates = duplicated_events.to_a
          return if duplicates.empty?

          duplicates.each do |transaction_id, event_timestamp, charge_id, charge_filter_id, max_enriched_at|
            Events::Stores::Utils::ClickhouseConnection.with_retry do
              base_scope
                .where(transaction_id:, timestamp: event_timestamp, charge_id:, charge_filter_id:)
                .where(enriched_at: ...max_enriched_at)
                .delete_all
            end
          end
        end
      end
    end
  end
end
