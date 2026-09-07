# frozen_string_literal: true

module Events
  module Stores
    # Mints the event store instances used by a single usage or billing computation.
    # Stateful and scoped to one computation at one window: build one per request or
    # per job, never at class level.
    class Provider
      def initialize(organization:, subscription:, boundaries:)
        @organization = organization
        @subscription = subscription
        @boundaries = boundaries
      end

      attr_reader :subscription, :boundaries

      # A store minted here answers for the provider's subscription and window only. An
      # aggregation running on another one has to build its own provider, or it would
      # silently read a different scope than it computes on: `max_timestamp` in particular
      # is attached per charge, and per pay-in-advance event.
      def scoped_to?(subscription:, boundaries:)
        self.subscription == subscription && self.boundaries == boundaries
      end

      # NOTE: never share the instance between charges, the aggregators write their own
      #       state (aggregation_property, numeric_property, use_from_boundary) into it.
      def store_for(charge:, filters: {})
        plain_store(code: charge.billable_metric.code, filters:)
      end

      def plain_store(code: nil, filters: {})
        store_class.new(code:, subscription:, boundaries:, filters:, deduplicate:)
      end

      def store_class
        @store_class ||= Events::Stores::StoreFactory.store_class(organization:)
      end

      def deduplicate
        return @deduplicate if defined?(@deduplicate)

        override = Events::Stores::StoreFactory.override
        @deduplicate = if override
          override[:deduplicate]
        else
          organization.clickhouse_events_store? && organization.clickhouse_deduplication_enabled?
        end
      end

      private

      attr_reader :organization
    end
  end
end
