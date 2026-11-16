# frozen_string_literal: true

module Events
  module Stores
    # The Provider of a contract's current usage: serves the billing segments of metered products
    # from the product usage buckets RisingWave writes, and every other read from the events.
    #
    # A segment is served only when the buckets give the answer the events would: anything the
    # buckets cannot tell apart or did not aggregate the way Rails bills falls back to the events.
    class ContractUsageBucketsProvider
      def initialize(contract:, billing_context:)
        @contract = contract
        @provider = Provider.new(organization: contract.organization, billing_context:)
        @fetches = {}
      end

      delegate :billing_context, :store_class, to: :provider

      def store_for(metered_item:, boundaries:, filters: {}, aggregated_filter_ids: nil)
        store = provider.store_for(metered_item:, boundaries:, filters:, aggregated_filter_ids:)
        return store unless served_from_buckets?(metered_item:, boundaries:, filters:)

        UsageBucketStore.new(
          store,
          usage_buckets: fetch(boundaries).usage_buckets,
          charge_id: metered_item.invoiceable.id,
          charge_filter_id: bucket_filter_id(metered_item)
        )
      end

      # Asked by Fees::ChargeService before it builds an aggregator, so it stays free of queries
      # but the segment's own.
      def may_precompute_charge?(metered_item:, boundaries:, **)
        unsupported_reason(metered_item:, boundaries:).nil?
      end

      def unsupported_reason(metered_item:, boundaries:)
        return "disabled" unless enabled?
        return "not_a_billing_segment" unless metered_item.billing_segment
        return "unsupported_charge_model" unless RealtimeUsage::SUPPORTED_CHARGE_MODELS.include?(metered_item.charge_model)
        return "unsupported_aggregation_type" unless RealtimeUsage::SUPPORTED_AGGREGATION_TYPES.include?(metered_item.billable_metric.aggregation_type)
        return "pay_in_advance" if metered_item.pay_in_advance?
        # A recurring metric reads every period since the contract started, and contracts keep no
        # snapshot the buckets of the window could complete. A prorated card always has one.
        return "recurring_metric" if metered_item.billable_metric.recurring?
        return "max_timestamp" if boundaries[:max_timestamp].present?
        return "unaligned_window" unless aligned_window?(boundaries)

        "filter_precedence" if filter_precedence_differs?(metered_item)
      end

      private

      attr_reader :contract, :provider, :fetches

      def enabled?
        return @enabled if defined?(@enabled)

        @enabled = contract.organization.product_events_pipeline? && RealtimeUsage.enabled?(contract.organization)
      end

      def served_from_buckets?(metered_item:, boundaries:, filters:)
        return false unless may_precompute_charge?(metered_item:, boundaries:)
        return false unless filters[:grouped_by_values].blank? &&
          filters[:event].blank? &&
          filters[:presentation_by].blank?

        fetch = fetch(boundaries)
        # An empty set is no proof the pipeline wrote this window: a zero it served could be lag.
        return false unless fetch.success? && fetch.usage_buckets.present?

        expected_keys = metered_item.pricing_group_keys.sort
        fetch.group_keys.fetch([metered_item.invoiceable.id, bucket_filter_id(metered_item)], Set.new)
          .all? { |keys| keys == expected_keys }
      end

      # The segment's card prices one product filter, or the default bucket, which the stream
      # writes as an empty string.
      def bucket_filter_id(metered_item)
        metered_item.product_filter&.id || ""
      end

      # The buckets are 15-minute tumbling windows, so a window must start and end on a bucket
      # wall. Billing cycles turn at customer-local midnights, which always do; a contract ending
      # or terminated inside a bucket does not.
      def aligned_window?(boundaries)
        from = boundaries[:from_datetime]
        to = ::BillingSegment.exclusive_end(boundaries[:to_datetime])

        RealtimeUsage.floor_to_bucket(from) == from && RealtimeUsage.floor_to_bucket(to) == to
      end

      # The stream bills an event on the filter of highest precedence among the product's filters,
      # and drops it when the contract prices none for that filter. Rails first prefers the filters
      # the contract prices (Events::BillingPeriodFilters::Sources::BillingSegment), so the two only
      # agree when no overlapping filter changes rank between both orders. The default bucket ranks
      # after every filter in both.
      def filter_precedence_differs?(metered_item)
        selected = metered_item.product_filter
        return false if selected.nil?

        target = Events::BillingPeriodFilters::FilterTarget.from_billing_segment(
          billing_segment: metered_item.billing_segment,
          filter: selected
        )
        selected_values = target.filter_values(selected)

        target.filters.any? do |filter|
          next false if filter.id == selected.id
          next false unless overlapping?(target.filter_values(filter), selected_values)

          rails_first = (target.filter_precedence(filter) <=> target.filter_precedence(selected)).negative?
          stream_first = (filter.precedence <=> selected.precedence).negative?
          rails_first != stream_first
        end
      end

      # Two filters overlap when every key they share allows a common value.
      def overlapping?(values, other_values)
        values.all? { |key, allowed| !other_values.key?(key) || allowed.intersect?(other_values[key]) }
      end

      # One read per window, for every product of the contract: the cards of a contract usually
      # share their billing cycle.
      def fetch(boundaries)
        window = [boundaries[:from_datetime], ::BillingSegment.exclusive_end(boundaries[:to_datetime])]

        fetches[window] ||= begin
          fetch = RealtimeUsage::FetchProductBucketsService.call(
            contract:,
            from_datetime: window.first,
            to_datetime: window.last
          )
          # Only the parity comparison opens the gate, and there a silent fallback would compare
          # the events with themselves.
          fetch.raise_if_error! if RealtimeUsage.forced_gate?
          fetch
        end
      end
    end
  end
end
