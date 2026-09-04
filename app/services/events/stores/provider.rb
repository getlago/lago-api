# frozen_string_literal: true

module Events
  module Stores
    # It is the only place that knows whether a (charge, filter) was served from the buckets or
    # delegated to the events store, and why, so it is the only place that reports it.
    class Provider
      def initialize(organization:, billing_context:, serve_current_usage_from_buckets: false,
        boundaries: nil, usage_filters: UsageFilters::NONE, charges: [])
        @organization = organization
        @billing_context = billing_context
        @serve_current_usage_from_buckets = serve_current_usage_from_buckets
        @boundaries = boundaries
        @usage_filters = usage_filters
        @charges = charges
        @outcomes = {}
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
          RealtimeUsage.enabled?(organization) &&
          !RealtimeUsage.deduplicated?(organization)
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

      attr_reader :organization, :serve_current_usage_from_buckets, :boundaries, :usage_filters,
        :charges, :outcomes

      # A full usage window opens on `subscription.started_at`, which `same_window_as_prefetch?`
      # cannot tell apart from a first billing period.
      def whole_charge_read?
        !usage_filters.full_usage && usage_filters.filter_by_group.blank?
      end

      # Both the store minting and the metric come through here, so the outcome is memoized and
      # a lookup is reported once per (charge, filter, window).
      def served_from_buckets?(metered_item:, boundaries:, filters: {})
        return false unless serve_current_usage_from_buckets

        key = [metered_item.charge&.id, filters[:charge_filter]&.id || "", boundaries]
        return outcomes[key] if outcomes.key?(key)

        outcomes[key] = report(delegation_reason(metered_item:, boundaries:, filters:))
      end

      # Asked once per (charge, filter) otherwise, on the path the buckets exist to make fast.
      def gate_open?
        return @gate_open if defined?(@gate_open)

        @gate_open = RealtimeUsage.enabled?(organization)
      end

      # nil when the buckets answer. The reason returned is the first thing that would have to
      # change for this lookup to be served, so a plan of ineligible charges reports what makes
      # them ineligible rather than the absent prefetch that ineligibility caused.
      #
      # The buckets close 15 minutes at a time, so they always lag: current usage can read a
      # lagging total, an invoice cannot. A `max_timestamp` freezes the read below the window
      # the totals cover, which would overcount by everything that landed after it.
      #
      # A window without a single bucket is a pipeline gap rather than an absence of usage:
      # answering zero would undercharge.
      #
      # `not_prefetched` covers a caller that declined the prefetch — `full_usage` and projected
      # reads do — a window other than the prefetched one, and a ClickHouse read that failed,
      # which already reaches Sentry.
      def delegation_reason(metered_item:, boundaries:, filters:)
        return :gate_disabled unless gate_open?
        return :deduplicated if RealtimeUsage.deduplicated?(organization)
        return :frozen_window if boundaries[:max_timestamp].present?
        return :ineligible_charge unless eligible_charge?(metered_item)
        return :unsupported_read unless whole_charge_read?
        return :unsupported_read if unsupported_read?(filters)
        return :not_prefetched unless same_window_as_prefetch?(boundaries)

        # Asked last so the ClickHouse read is skipped when no charge of the plan could use it.
        return :not_prefetched if usage_buckets.nil?
        return :no_buckets if usage_buckets.empty?

        :drift unless usage_buckets.serves_charge?(metered_item.charge.id)
      end

      # The buckets are keyed by charge, and a billing segment is priced from its product rather
      # than from the optional legacy charge that product may carry.
      def eligible_charge?(metered_item)
        return false if metered_item.billing_segment

        charge = metered_item.charge
        return false if charge.nil?

        RealtimeUsage.supported_charge?(charge)
      end

      # The totals answer for the whole (charge, filter), so a group-scoped or pay-in-advance
      # read cannot use them, and a presentation breakdown reads events anyway.
      def unsupported_read?(filters)
        filters[:grouped_by_values].present? ||
          filters[:event].present? ||
          filters[:presentation_by].present?
      end

      # Nothing is reported for an organization the gate is shut for, or the disabled buckets
      # would drown the ratio.
      def report(reason)
        served = reason.nil?
        return served unless gate_open?

        Yabeda.realtime_usage.lookups_total.increment(
          {outcome: served ? "served" : "delegated", reason: reason&.to_s || "none"}
        )
        report_freshness if served

        served
      end

      # Once per computation: the watermark answers for the whole prefetched set, not for the
      # charge that happened to be looked up first.
      def report_freshness
        return if @freshness_reported

        @freshness_reported = true
        ingested_at = usage_buckets.last_ingested_at
        return if ingested_at.nil?

        Yabeda.realtime_usage.freshness.measure({}, (Time.current - ingested_at).to_f)
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
