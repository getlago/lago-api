# frozen_string_literal: true

module Events
  module Stores
    # Mints the event store instances used by a single usage or billing computation, and
    # holds the pre-aggregated usage buckets it may serve count and sum from.
    #
    # Scoped to one computation at one window: build one per request or job.
    class Provider
      def initialize(organization:, subscription:, boundaries:, usage_buckets: nil, current_usage: false)
        @organization = organization
        @subscription = subscription
        @boundaries = boundaries
        @usage_buckets = usage_buckets
        @current_usage = current_usage
      end

      attr_reader :subscription, :boundaries

      # A store minted here answers for the provider's subscription and window only. An
      # aggregation running on another one has to build its own provider, or it would
      # silently read a different scope than it computes on: `max_timestamp` in particular
      # is attached per charge, and per pay-in-advance event.
      def scoped_to?(subscription:, boundaries:)
        self.subscription == subscription && self.boundaries == boundaries
      end

      def scoped_to!(subscription:, boundaries:)
        return if scoped_to?(subscription:, boundaries:)

        raise ArgumentError, "event store provider is scoped to another subscription or window"
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

      # nil when this computation does not serve from buckets. An empty set is not nil: it
      # means the prefetch ran and found no usage.
      attr_reader :usage_buckets

      # Options to merge into those passed to `aggregate`, or none when the charge has to
      # read events.
      def precomputed_options_for(charge:, filters: {})
        return {} unless serves?(charge:, filters:)

        charge_id = charge.id
        charge_filter_id = self.class.bucket_charge_filter_id(filters[:charge_filter])

        {
          precomputed_aggregation: usage_buckets.aggregation_result_for(charge_id:, charge_filter_id:),
          precomputed_grouped_aggregations: usage_buckets.grouped_aggregation_results_for(charge_id:, charge_filter_id:)
        }
      end

      # Whether this (charge, filter) is answered from the buckets. The totals answer for the
      # whole (charge, filter), so a group-scoped or pay-in-advance read cannot use them, and
      # a presentation breakdown reads events anyway. A window without a single bucket is a
      # pipeline gap rather than an absence of usage: answering zero would undercharge.
      #
      # The buckets close 15 minutes at a time, so they always lag: current usage can read a
      # lagging total, an invoice cannot. A `max_timestamp` freezes the read below the window
      # the totals cover, which would overcount by everything that landed after it.
      def serves?(charge:, filters: {})
        return false if usage_buckets.blank?
        return false unless current_usage
        return false if boundaries[:max_timestamp].present?
        return false unless RealtimeUsage.enabled?(organization)
        return false if RealtimeUsage.deduplicated?(organization)
        return false unless RealtimeUsage.supported_charge?(charge)
        return false unless usage_buckets.serves_charge?(charge.id)

        filters[:grouped_by_values].blank? &&
          filters[:event].blank? &&
          filters[:presentation_by].blank? &&
          filters[:filter_by_group].blank?
      end

      # The sink writes `COALESCE(charge_filter_id, '')`, while the unfiltered fee carries
      # an unpersisted ChargeFilter whose id is nil.
      def self.bucket_charge_filter_id(charge_filter)
        charge_filter&.id || ""
      end

      private

      attr_reader :organization, :current_usage
    end
  end
end
