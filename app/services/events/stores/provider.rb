# frozen_string_literal: true

module Events
  module Stores
    class Provider
      def initialize(organization:, billing_context:, serve_current_usage_from_buckets: false,
        boundaries: nil, usage_filters: UsageFilters::NONE, charges: [])
        @organization = organization
        @billing_context = billing_context
        @serve_current_usage_from_buckets = serve_current_usage_from_buckets
        @boundaries = boundaries
        @usage_filters = usage_filters
        @charges = charges
      end

      attr_reader :billing_context

      def store_for(metered_item:, boundaries:, filters: {})
        store = store_class.new(
          code: metered_item.billable_metric.code,
          billing_context:,
          boundaries:,
          filters:,
          deduplicate:
        )
        if served_from_buckets?(metered_item:, boundaries:, filters:)
          UsageBucketStore.new(
            store,
            usage_buckets:,
            charge_id: metered_item.charge.id,
            charge_filter_id: filters[:charge_filter]&.id || "" # clickhouse stores an empty string instead of nil
          )
        else
          store
        end
      end

      # Callers ask this before building anything, so it must stay free of queries and per-charge work.
      def may_precompute?
        return @may_precompute if defined?(@may_precompute)

        @may_precompute = serve_current_usage_from_buckets &&
          whole_charge_read? &&
          RealtimeUsage.enabled?(organization)
      end

      # Every gate a charge can be ruled out by before an aggregator and a store exist, so that
      # a charge the buckets cannot answer costs nothing to skip.
      def may_precompute_charge?(metered_item:, boundaries:)
        return false unless may_precompute?
        # The buckets are keyed by charge, and a billing segment is priced from its product
        # rather than from the optional legacy charge that product may carry.
        return false if metered_item.billing_segment

        charge = metered_item.charge
        return false if charge.nil?
        return false if boundaries[:max_timestamp].present?
        return false unless same_window_as_prefetch?(boundaries)

        RealtimeUsage.supported_charge?(charge)
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

      attr_reader :organization, :serve_current_usage_from_buckets, :boundaries, :usage_filters, :charges

      # A full usage window opens on `subscription.started_at`, which `same_window_as_prefetch?`
      # cannot tell apart from a first billing period.
      def whole_charge_read?
        !usage_filters.full_usage && usage_filters.filter_by_group.blank?
      end

      def served_from_buckets?(metered_item:, boundaries:, filters: {})
        return false unless may_precompute_charge?(metered_item:, boundaries:)
        return false unless filters[:grouped_by_values].blank? &&
          filters[:event].blank? &&
          filters[:presentation_by].blank?

        # Asked last so the ClickHouse read is skipped when no charge of the plan could use it.
        # An empty set is no proof the pipeline wrote this window, so it falls back to the events
        # store rather than serving a zero a lagging pipeline cannot be told apart from.
        usage_buckets.present?
      end

      def same_window_as_prefetch?(window)
        return false if boundaries.nil?

        window[:from_datetime] == boundaries.charges_from_datetime &&
          window[:to_datetime] == boundaries.charges_to_datetime
      end

      # `call` rather than `call!`: an unreachable ClickHouse has to make current usage slow,
      # not broken. A nil set falls back to the events store.
      def usage_buckets
        return @usage_buckets if defined?(@usage_buckets)

        @usage_buckets = if serve_current_usage_from_buckets && bucket_charges.any?
          RealtimeUsage::FetchBucketsService
            .call(subscription: billing_context.subscription, boundaries:, charges: bucket_charges)
            .usage_buckets
        end
      end

      # The charges the buckets could answer. A plan whose charges are all recurring, prorated or
      # pay-in-advance pays no bucket read at all, and the ones left scope that read to the
      # table's `organization_id, subscription_id, charge_id` prefix.
      def bucket_charges
        @bucket_charges ||= charges.select { RealtimeUsage.supported_charge?(it) }
      end
    end
  end
end
