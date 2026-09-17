# frozen_string_literal: true

module Events
  module Stores
    # Mints the event store instances used by a single usage or billing computation, and
    # holds the pre-aggregated usage buckets it may serve count and sum from.
    #
    # It is also the only place that knows whether a (charge, filter) was served or delegated
    # and why, so it is the only place that reports it.
    #
    # Scoped to one computation at one window: build one per request or job.
    class Provider
      def initialize(organization:, subscription:, boundaries:, usage_buckets: nil, current_usage: false)
        @organization = organization
        @subscription = subscription
        @boundaries = boundaries
        @usage_buckets = usage_buckets
        @current_usage = current_usage
        @outcomes = {}
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

      # Whether this (charge, filter) is answered from the buckets. Both callers of the decision
      # — the charge cache bypass and the aggregation options — come through here, so the
      # outcome is memoized and a lookup is reported once.
      def serves?(charge:, filters: {})
        return false unless current_usage

        key = [charge.id, self.class.bucket_charge_filter_id(filters[:charge_filter])]
        return outcomes[key] if outcomes.key?(key)

        outcomes[key] = report(delegation_reason(charge:, filters:))
      end

      # The sink writes `COALESCE(charge_filter_id, '')`, while the unfiltered fee carries
      # an unpersisted ChargeFilter whose id is nil.
      def self.bucket_charge_filter_id(charge_filter)
        charge_filter&.id || ""
      end

      private

      attr_reader :organization, :current_usage, :outcomes

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
      # `not_prefetched` covers both a caller that declined the prefetch — `full_usage` and
      # projected reads do — and a ClickHouse read that failed, which already reaches Sentry.
      def delegation_reason(charge:, filters:)
        return :gate_disabled unless gate_open?
        return :deduplicated if RealtimeUsage.deduplicated?(organization)
        return :frozen_window if boundaries[:max_timestamp].present?
        return :ineligible_charge unless RealtimeUsage.supported_charge?(charge)
        return :unsupported_read if unsupported_read?(filters)
        return :not_prefetched if usage_buckets.nil?
        return :no_buckets if usage_buckets.empty?

        :drift unless usage_buckets.serves_charge?(charge.id)
      end

      # The totals answer for the whole (charge, filter), so a group-scoped or pay-in-advance
      # read cannot use them, and a presentation breakdown reads events anyway.
      def unsupported_read?(filters)
        filters[:grouped_by_values].present? ||
          filters[:event].present? ||
          filters[:presentation_by].present? ||
          filters[:filter_by_group].present?
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
    end
  end
end
