# frozen_string_literal: true

module Events
  class BillingPeriodFilterService < BaseService
    Result = BaseResult[:charges]

    # current_usage mirrors BillableMetrics::AggregationFactory: it is the only context where
    # realtime-eligible charges are aggregated from the RisingWave-fed usage buckets, so it is
    # also the only context where their charge/filter set may be read from there. Invoicing and
    # preview keep resolving everything from the events store.
    def initialize(subscription:, boundaries:, codes: nil, with_last_seen_at: true, current_usage: false)
      @subscription = subscription
      @boundaries = boundaries
      @codes = codes
      @with_last_seen_at = with_last_seen_at
      @current_usage = current_usage
      super
    end

    # Return the charges and filters that will be used in the billing or usage computation.
    #
    # result.charges is a nested hash: { charge_id => { filter_id => last_seen_at } } (nil filter
    # is the default bucket). last_seen_at is the most recent event ingestion timestamp for that
    # charge/filter (created_at on PG, enriched_at on CH), used to lazily invalidate the cache.
    # It is nil when with_last_seen_at is disabled, which keeps a cached entry valid forever.
    # Recurring charges with no in-period event are seeded with the period start (see #period_start).
    def call
      result.charges = charges_and_filters
      result
    end

    private

    attr_reader :subscription, :boundaries, :codes, :with_last_seen_at, :current_usage

    delegate :plan, :organization, to: :subscription

    # Floor for recurring charges without events: seeding last_seen_at here (instead of nil) lets
    # any in-period event invalidate the lazy cache, which nil would keep valid forever.
    def period_start
      boundaries.charges_from_datetime
    end

    def event_store
      @event_store ||= Events::Stores::StoreFactory.new_instance(
        organization: organization,
        subscription:,
        boundaries: {
          from_datetime: boundaries.charges_from_datetime,
          to_datetime: boundaries.charges_to_datetime
        }
      )
    end

    # A code outside of the plan matches no event, so codes is used as is: dropping it would leave
    # its charge out of the result, billed as zero units instead of surfaced.
    def plan_codes
      @plan_codes ||= codes || plan.billable_metrics.distinct.pluck(:code)
    end

    def charges_and_filters
      return charges_and_filters_from_events unless organization.pre_filter_events?

      charges_and_filters_from_pre_enriched_events
    end

    # { charge_id => { filter_id => last_seen_at } } (nil filter is the default bucket).
    # Recurring charges are seeded first (usage carries over); then matching events resolve the
    # filters for non-recurring charges and refresh last_seen_at for recurring ones.
    def charges_and_filters_from_events
      combinations = event_store.distinct_codes_and_property_combinations(
        codes: non_recurring_plan_codes,
        filter_keys: billable_metric_filter_keys,
        with_last_seen_at:
      )

      # Recurring usage carries over all-time, so its lazy cache key must reflect events ingested
      # for prior periods
      if recurring_plan_codes.any?
        combinations += event_store.distinct_codes_and_property_combinations(
          codes: recurring_plan_codes,
          filter_keys: billable_metric_filter_keys,
          include_all_history: true,
          with_last_seen_at:
        )
      end

      # Group the [code, properties, last_seen_at] tuples by code
      combinations_by_code = combinations.group_by(&:first)

      # Recurring charges must always be billed as usage carries over from previous periods
      result = recurring_event_charges_and_filters

      charges_with_events(combinations_by_code.keys).each do |charge|
        code = charge.billable_metric.code

        combinations_by_code[code].each do |(_code, properties, last_seen_at)|
          event = ::Event.new(code:, properties:)
          matching = ChargeFilters::EventMatchingService.call(charge:, event:).matching_charge_filters

          # No filter matches: the usage falls into the default bucket.
          # Otherwise include every matching filter and let the aggregation cascade
          # assign the event to the most specific one (the others aggregate to zero).
          if matching.empty?
            record(result, charge.id, nil, last_seen_at)
          else
            matching.each { |filter| record(result, charge.id, filter.id, last_seen_at) }
          end
        end
      end

      result
    end

    # Add a charge/filter to the accumulator, keeping the most recent last_seen_at (nil never
    # overwrites an existing timestamp). Filters are hash keys, so pairs are deduplicated.
    def record(accumulator, charge_id, filter_id, last_seen_at)
      bucket = (accumulator[charge_id] ||= {})
      current = bucket[filter_id]

      if !bucket.key?(filter_id) || (last_seen_at && (current.nil? || last_seen_at > current))
        bucket[filter_id] = last_seen_at
      end
    end

    # Recurring charges and all their filters (including the default bucket).
    # They are always returned, even without events, as usage carries over.
    def recurring_event_charges_and_filters
      result = {}

      plan.charges.joins(:billable_metric).left_joins(:filters)
        .where(billable_metrics: {recurring: true})
        .group("charges.id, charge_filters.id")
        .pluck("charges.id", "charge_filters.id")
        .each { |charge_id, filter_id| record(result, charge_id, filter_id, period_start) }

      # Recurring charges always expose the default (no-filter) bucket
      result.each_key { |charge_id| record(result, charge_id, nil, period_start) }
      result
    end

    # Charges of the plan whose billable metric received events in the period (recurring or not)
    def charges_with_events(codes)
      plan.charges
        .joins(:billable_metric)
        .where(billable_metrics: {code: codes})
        .includes(billable_metric: :filters, filters: {values: :billable_metric_filter})
    end

    # Union of every filter key defined across the billable metrics the lookup covers
    def billable_metric_filter_keys
      @billable_metric_filter_keys ||= BillableMetricFilter
        .where(billable_metric_id: plan.billable_metrics.where(code: plan_codes).select(:id))
        .distinct
        .pluck(:key)
    end

    # Return the charges and filters matching the events pre-enriched in ClickHouse or Postgres for
    # the period, including the recurring ones, except in the first period where they are only
    # returned when the event lookup covers their code.
    # Shape: { charge_id => { filter_id => last_seen_at } } (nil filter is the default bucket).
    def charges_and_filters_from_pre_enriched_events
      values = realtime_charges_and_filters
      if events_store_codes.any?
        values += event_store.distinct_charges_and_filters(codes: events_store_codes, with_last_seen_at:)
      end

      # Recurring usage carries over all-time, so its lazy cache key must reflect events ingested
      # for prior periods
      if recurring_plan_codes.any?
        values += event_store.distinct_charges_and_filters(
          codes: recurring_plan_codes,
          include_all_history: true,
          with_last_seen_at:
        )
      end

      charge_filter_ids = values.map { |v| v[1] }.reject(&:blank?)
      charge_ids = values.map(&:first).uniq

      existing_charge_ids = plan.charges.where(id: charge_ids).pluck(:id)
      existing_charge_filters = fetch_existing_filters(charge_filter_ids)

      result = recurring_charges_and_filters

      values.each do |charge_id, filter_id, last_seen_at|
        # Charge has been removed from the plan
        next unless existing_charge_ids.include?(charge_id)

        # Charge has no filters or only default bucket received usage in the period
        if filter_id.blank?
          record(result, charge_id, nil, last_seen_at)
          next
        end

        # Keep only existing filters
        next unless existing_charge_filters.include?(filter_id)
        record(result, charge_id, filter_id, last_seen_at)
      end

      result
    end

    # [charge_id, charge_filter_id, last_seen_at] triples for the realtime-eligible charges, read
    # from the RisingWave-fed 15-minute buckets (Clickhouse::UsageBucket) instead of the events
    # store. The buckets already hold one row per (charge, filter, group, 15 minutes), which is the
    # exact grain this lookup needs, so it costs a handful of rows where the equivalent
    # events_enriched_expanded query has to aggregate every event of the period.
    #
    # last_seen_at is nil by design. It only drives the lazy charge cache, and
    # Invoices::CustomerUsageService disables that cache for realtime-eligible charges, so nothing
    # reads it here. Returning the buckets' last_ingested_at instead would put the API ingest clock
    # and ClickHouse's enriched_at into the same comparison the cache makes across reads, which is
    # how a cached entry would end up either stale forever or never valid.
    def realtime_charges_and_filters
      @realtime_charges_and_filters ||= if realtime_charges.empty?
        []
      else
        Events::Stores::Utils::ClickhouseConnection.with_retry do
          ::Clickhouse::UsageBucket.final
            .where(
              organization_id: subscription.organization_id,
              subscription_id: subscription.id,
              charge_id: realtime_charges.map(&:id)
            )
            .where("bucket >= ? AND bucket <= ?", bucket_window_from, bucket_window_to)
            .group(:charge_id, :charge_filter_id)
            .pluck(:charge_id, Arel.sql("nullIf(charge_filter_id, '')"), Arel.sql("NULL"))
        end
      end
    end

    # Charges whose current usage is served from the buckets. Eligibility is per charge, and a
    # recurring metric is never eligible, so this only ever covers non-recurring codes and the
    # recurring lookup is left on the events store.
    def realtime_charges
      @realtime_charges ||= if current_usage && RealtimeUsage.enabled?
        non_recurring_charges.select { RealtimeUsage.eligible_charge?(it) }
      else
        []
      end
    end

    def non_recurring_charges
      @non_recurring_charges ||= plan.charges
        .joins(:billable_metric)
        .where(billable_metrics: {code: non_recurring_plan_codes})
        .includes(:billable_metric)
        .to_a
    end

    # Non-recurring codes the events store still has to resolve: everything not fully covered by
    # the buckets. Codes outside the plan have no charge to cover them, so they stay here too.
    def events_store_codes
      @events_store_codes ||= non_recurring_plan_codes - bucket_served_codes
    end

    # A code is served by the buckets only when every one of its charges is realtime-eligible AND
    # returned at least one bucket row. Both halves matter:
    #
    #  * one ineligible charge on the code and the events store has to run anyway, and it returns
    #    the eligible charges of that code as well, so nothing is lost by leaving the code here;
    #  * no bucket row for an eligible charge means the same empty window that makes the realtime
    #    aggregators fall back to the events store (see BucketLookup). Without this fallback a
    #    RisingWave gap would drop the charge from filtered_aggregations and Fees::ChargeService
    #    would hydrate a zero-units fee, hiding usage the fallback aggregation does find.
    #
    # Bucket rows for a code that ends up here are still returned: #record merges the two sources
    # by (charge, filter) and the events store's last_seen_at wins over the nil above.
    def bucket_served_codes
      covered_charge_ids = realtime_charges_and_filters.map(&:first).to_set

      if covered_charge_ids.empty?
        []
      else
        non_recurring_charges
          .group_by { it.billable_metric.code }
          .select { |_code, charges| charges.all? { covered_charge_ids.include?(it.id) } }
          .keys
      end
    end

    def bucket_window_from
      @bucket_window_from ||= RealtimeUsage.bucket_floor(period_start)
    end

    def bucket_window_to
      boundaries.charges_to_datetime || Time.current
    end

    def recurring_charges_and_filters
      # First period: no previous usage exists, events from current period are enough
      return {} if subscription.started_at >= boundaries.charges_from_datetime

      # If the subscription was upgraded, use the upgrade chain to filter recurring charges
      return recurring_charges_and_filters_from_upgrade_chain if subscription.previous_subscription_id.present?

      # Use previous fees to filter the recurring charges with existing usage
      recurring_charges_and_filters_from_previous_fees
    end

    def recurring_charges_and_filters_from_previous_fees
      pairs = current_subscription_recurring_fees

      return {} if pairs.empty?

      filter_ids = pairs.map(&:last).compact
      if filter_ids.any?
        existing_filter_ids = fetch_existing_filters(filter_ids)
        pairs = pairs.select { |_, f_id| f_id.nil? || existing_filter_ids.include?(f_id) }
      end

      group_by_charge_id(pairs)
    end

    def recurring_charges_and_filters_from_upgrade_chain
      # First, let's fetch fees from the current subscription created before the current period
      result = group_by_charge_id(current_subscription_recurring_fees)

      # Then, include all filters for charges whose billable metric had previous usage
      previous_bm_ids = previous_subscriptions_billable_metric_ids
      return result if previous_bm_ids.empty?

      current_recurring_charges.each do |charge|
        next unless previous_bm_ids.include?(charge.billable_metric_id)

        charge.filters.each { |filter| record(result, charge.id, filter.id, period_start) }
        record(result, charge.id, nil, period_start)
      end
      result
    end

    def recurring_plan_codes
      @recurring_plan_codes ||= plan.billable_metrics.where(recurring: true).where(code: plan_codes).distinct.pluck(:code)
    end

    def non_recurring_plan_codes
      @non_recurring_plan_codes ||= plan_codes - recurring_plan_codes
    end

    # Fetches all recurring charges for the current plan
    def current_recurring_charges
      @current_recurring_charges ||= plan.charges
        .joins(:billable_metric)
        .where(billable_metrics: {recurring: true})
        .includes(:filters)
        .to_a
    end

    # Fetches all recurring billable metrics IDs from previous subscriptions,
    # still used in the current plan
    def previous_subscriptions_billable_metric_ids
      previous_sub_ids = collect_previous_subscription_ids
      return Set.new if previous_sub_ids.empty?

      bm_ids = current_recurring_charges.map(&:billable_metric_id)
      return Set.new if bm_ids.empty?

      Fee.where(subscription_id: previous_sub_ids, fee_type: :charge)
        .joins(charge: :billable_metric)
        .where(billable_metrics: {id: bm_ids})
        .positive_units
        .distinct
        .pluck(:billable_metric_id)
        .to_set
    end

    # Fetches all terminated subscription IDs sharing the same external_id
    def collect_previous_subscription_ids
      organization.subscriptions
        .terminated
        .where(external_id: subscription.external_id, customer_id: subscription.customer_id)
        .where.not(id: subscription.id)
        .pluck(:id)
    end

    # Fetchs all recurring fees created for the current subscription before the current billing period
    def current_subscription_recurring_fees
      Fee.where(subscription_id: subscription.id, fee_type: :charge)
        .joins(invoice: :invoice_subscriptions)
        .where("invoice_subscriptions.subscription_id = fees.subscription_id")
        .where("invoice_subscriptions.charges_from_datetime < ?", boundaries.charges_from_datetime)
        .joins(charge: :billable_metric)
        .where(charges: {plan_id: plan.id, deleted_at: nil})
        .where(billable_metrics: {recurring: true})
        .positive_units
        .distinct
        .pluck(:charge_id, :charge_filter_id)
    end

    # Group recurring charge/filter pairs from previous fees, seeded with the period start.
    def group_by_charge_id(rows)
      rows.each_with_object({}) do |(charge_id, filter_id), accumulator|
        record(accumulator, charge_id, filter_id, period_start)
      end
    end

    def fetch_existing_filters(charge_filter_ids)
      plan.charges.joins(:filters)
        .where(charge_filters: {id: charge_filter_ids})
        .pluck("charge_filters.id")
    end
  end
end
