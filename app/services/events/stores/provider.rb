# frozen_string_literal: true

module Events
  module Stores
    class Provider
      def initialize(organization:, billing_context:, current_usage: false, serve_from_buckets: false,
        boundaries: nil, usage_filters: UsageFilters::NONE)
        @organization = organization
        @billing_context = billing_context
        @current_usage = current_usage
        @serve_from_buckets = serve_from_buckets
        @boundaries = boundaries
        @usage_filters = usage_filters
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
            # The sink writes `COALESCE(charge_filter_id, '')`, while the unfiltered fee carries an
            # unpersisted ChargeFilter whose id is nil.
            charge_filter_id: filters[:charge_filter]&.id || ""
          )
        else
          store
        end
      end

      # Whether any store this provider mints could answer from a precomputed source. Every gate
      # that does not depend on the charge is asked here, so a caller can skip the per-charge work
      # it would only need in order to ask a single store the same question. Cheap by
      # construction: no query, no per-charge work.
      def may_precompute?
        return @may_precompute if defined?(@may_precompute)

        @may_precompute = current_usage &&
          serve_from_buckets &&
          whole_charge_read? &&
          RealtimeUsage.enabled?(organization) &&
          !RealtimeUsage.deduplicated?(organization)
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

      attr_reader :organization, :current_usage, :serve_from_buckets, :boundaries, :usage_filters

      # A lifetime window opens on `subscription.started_at`, which nothing downstream tells apart
      # from a first billing period. A read restricted to some pricing group values asks for less
      # than the charge total the buckets hold.
      def whole_charge_read?
        !usage_filters.full_usage && usage_filters.filter_by_group.blank?
      end

      def served_from_buckets?(metered_item:, boundaries:, filters: {})
        return false unless may_precompute?
        # The buckets are keyed by charge, and a billing segment is priced from its product
        # rather than from the optional legacy charge that product may carry.
        return false if metered_item.billing_segment

        charge = metered_item.charge
        return false if charge.nil?
        return false if boundaries[:max_timestamp].present?
        return false unless same_window_as_prefetch?(boundaries)
        return false unless RealtimeUsage.supported_charge?(charge)
        return false unless filters[:grouped_by_values].blank? &&
          filters[:event].blank? &&
          filters[:presentation_by].blank?

        # Asked last, so the ClickHouse read stays off a plan no charge of which can use it. A set
        # that holds no row for this charge is served as no usage: this gates on what the buckets
        # can answer, never on whether the pipeline has caught up.
        !usage_buckets.nil?
      end

      # The buckets are fetched for the window this provider was built with, so a store asked for
      # any other window cannot be answered from them.
      def same_window_as_prefetch?(window)
        return false if boundaries.nil?

        window[:from_datetime] == boundaries.charges_from_datetime &&
          window[:to_datetime] == boundaries.charges_to_datetime
      end

      # Fetched once for the whole computation, so every charge it serves is answered by a single
      # ClickHouse query. nil when this computation reads events, which covers a window the
      # buckets cannot answer as well as a read that failed: `call` rather than `call!`, as an
      # unreachable ClickHouse has to make current usage slow, not broken.
      def usage_buckets
        return @usage_buckets if defined?(@usage_buckets)

        @usage_buckets = if serve_from_buckets
          RealtimeUsage::FetchBucketsService.call(subscription: billing_context.subscription, boundaries:).usage_buckets
        end
      end
    end
  end
end
