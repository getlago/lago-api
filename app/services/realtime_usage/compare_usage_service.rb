# frozen_string_literal: true

module RealtimeUsage
  # Computes the current usage of one subscription twice, once served from the pre-aggregated
  # buckets and once from the events store, and compares them per (charge, charge filter, group).
  # Both runs share one timestamp and skip the charge cache, so only the two paths can explain a
  # difference, and the values are compared exactly: a tolerance would hide the precision bugs
  # this exists to find.
  class CompareUsageService < BaseService
    Result = BaseResult[
      :rows,
      :differences,
      :cutover_risks,
      :eligible_charges_count,
      :served_charges_count,
      :duplicate_events_count,
      :declined_reason,
      :rechecked
    ]

    # The ingestion time is written by ClickHouse, the comparison is timed by Rails: the margin
    # keeps a clock skew between the two from hiding an event that landed during the run.
    CLOCK_SKEW_MARGIN = 1.minute
    RECHECK_DELAY = 5.seconds

    MATCH = "match"
    MISMATCH = "mismatch"
    RESENT_TRANSACTION_ID = "resent_transaction_id"

    BUCKET_READ_FAILURE = "bucket_read_failure"

    Totals = Data.define(:units, :amount_cents, :events_count)
    EMPTY_TOTALS = Totals.new(units: BigDecimal(0), amount_cents: 0, events_count: 0)

    Row = Data.define(
      :charge_id,
      :billable_metric_code,
      :charge_filter_id,
      :grouped_by,
      :classification,
      :bucket_units,
      :events_units,
      :bucket_amount_cents,
      :events_amount_cents,
      :bucket_events_count,
      :events_events_count
    ) do
      def units_diff
        bucket_units - events_units
      end

      def amount_cents_diff
        bucket_amount_cents - events_amount_cents
      end

      def different?
        !units_diff.zero? || !amount_cents_diff.zero?
      end

      def mismatch?
        classification == MISMATCH
      end

      def cutover_risk?
        classification == RESENT_TRANSACTION_ID
      end
    end

    def initialize(subscription:, timestamp: Time.current)
      @subscription = subscription
      @timestamp = timestamp

      super
    end

    def call
      result.rechecked = false
      started_at = Time.current
      compare

      if result.differences.any? && events_received_since?(started_at - CLOCK_SKEW_MARGIN)
        sleep(RECHECK_DELAY)
        result.rechecked = true
        compare
      end

      result
    rescue BaseService::FailedResult => e
      result.fail_with_error!(e.result.error)
    end

    private

    attr_reader :subscription, :timestamp, :duplicate_events_by_code

    # The charges the buckets serve are known before any usage is computed, so both runs are
    # narrowed to them: a charge that cannot be compared is worth computing on neither side.
    def compare
      candidate_charges = RealtimeUsage.with_forced_gate { fetch_served_charges }

      result.rows = []
      result.differences = []
      result.cutover_risks = []
      result.duplicate_events_count = 0
      result.eligible_charges_count = eligible_charges.size
      result.served_charges_count = 0
      result.declined_reason = candidate_charges.empty? ? decline_reason : nil
      return if candidate_charges.empty?

      # The probe reads the buckets on its own, and a read failing inside the usage run falls back
      # to the events store without raising: taking the probe for an answer would compare the
      # events store with itself. Only the charges the run reports as served are compared.
      bucket_result = RealtimeUsage.with_forced_gate do
        compute_usage(use_usage_buckets: true, charge_ids: candidate_charges.map(&:id))
      end
      served_charges = candidate_charges.select { bucket_result.precomputed_charge_ids.include?(it.id) }
      result.served_charges_count = served_charges.size
      if served_charges.empty?
        result.declined_reason = BUCKET_READ_FAILURE
        return
      end

      @compared_codes = served_charges.map { it.billable_metric.code }.uniq
      served_charge_ids = served_charges.map(&:id).to_set
      events_usage = compute_usage(use_usage_buckets: false, charge_ids: served_charge_ids.to_a).usage

      @duplicate_events_by_code = fetch_duplicate_events_by_code(served_charges)

      result.rows = build_rows(bucket_usage: bucket_result.usage, events_usage:, served_charge_ids:)
      result.differences = result.rows.select(&:different?)
      result.cutover_risks = result.rows.select(&:cutover_risk?)
      result.duplicate_events_count = duplicate_events_by_code.values.sum
    end

    def compute_usage(use_usage_buckets:, charge_ids:)
      Invoices::CustomerUsageService.call!(
        customer: subscription.customer,
        subscription:,
        timestamp:,
        with_cache: false,
        apply_taxes: false,
        usage_filters: UsageFilters.new(filter_by_charge_id: charge_ids),
        use_usage_buckets:
      )
    end

    # Asks the provider itself which charges the buckets answered, rather than deducing it from
    # the fees: a charge the provider declined must never be read as a comparison. Asked exactly as
    # Invoices::CustomerUsageService asks it, presentation group keys included, so a charge the read
    # path serves from the events store on both sides is never compared with itself.
    def fetch_served_charges
      provider = Events::Stores::Provider.new(
        organization:,
        billing_context:,
        boundaries:,
        serve_current_usage_from_buckets: true,
        charges:
      )
      return [] unless provider.may_precompute?

      eligible_charges.select do |charge|
        metered_item = Fees::ChargeService::MeteredItem.from_charge(charge:, boundaries:)
        provider.serves_whole_charge_from_buckets?(
          metered_item:,
          boundaries: metered_item.aggregation_boundaries
        )
      end
    end

    def build_rows(bucket_usage:, events_usage:, served_charge_ids:)
      bucket_totals = comparable_totals(bucket_usage, served_charge_ids)
      events_totals = comparable_totals(events_usage, served_charge_ids)

      (bucket_totals.keys | events_totals.keys).map do |key|
        charge_id, charge_filter_id, grouped_by = key
        bucket = bucket_totals[key] || EMPTY_TOTALS
        events = events_totals[key] || EMPTY_TOTALS

        row = Row.new(
          charge_id:,
          billable_metric_code: charges_by_id[charge_id].billable_metric.code,
          charge_filter_id:,
          grouped_by:,
          classification: nil,
          bucket_units: bucket.units,
          events_units: events.units,
          bucket_amount_cents: bucket.amount_cents,
          events_amount_cents: events.amount_cents,
          bucket_events_count: bucket.events_count,
          events_events_count: events.events_count
        )

        row.with(classification: classify(row))
      end
    end

    def classify(row)
      return MATCH unless row.different?
      return RESENT_TRANSACTION_ID if resent_transaction_id?(row)

      MISMATCH
    end

    # The events store keeps the latest insert of a re-sent transaction id where the stream keeps
    # the first, which moves the units without moving the event count. The duplicates are counted
    # per metric code, which is the granularity the events store can answer cheaply, so this label
    # says a difference may be explained rather than that it is: the leaf is reported either way.
    def resent_transaction_id?(row)
      row.bucket_events_count == row.events_events_count &&
        duplicate_events_by_code[row.billable_metric_code].to_i.positive?
    end

    def comparable_totals(usage, served_charge_ids)
      (usage&.fees || []).each_with_object({}) do |fee, totals|
        next unless served_charge_ids.include?(fee.charge_id)

        key = [fee.charge_id, fee.charge_filter_id, normalized_groups(fee)]
        current = totals[key] || EMPTY_TOTALS
        totals[key] = Totals.new(
          units: current.units + fee.units.to_d,
          amount_cents: current.amount_cents + fee.amount_cents.to_i,
          events_count: current.events_count + fee.events_count.to_i
        )
      end
    end

    # The stream writes an absent group value as an empty string where the events store returns
    # nil, a label difference over identical units.
    def normalized_groups(fee)
      (fee.grouped_by || {}).transform_values { it.presence }
    end

    def decline_reason
      return "no_comparable_charges" if eligible_charges.empty?
      return "not_premium" unless License.premium?
      return "clickhouse_disabled" unless Events::Stores::StoreFactory.supports_clickhouse?
      return "postgres_events_store" unless organization.clickhouse_events_store?

      "no_buckets"
    end

    def fetch_duplicate_events_by_code(served_charges)
      return {} unless organization.clickhouse_events_store?

      CountDuplicateEventsService.call!(
        subscription:,
        codes: served_charges.map { it.billable_metric.code }.uniq,
        from_datetime: boundaries.charges_from_datetime,
        to_datetime: boundaries.charges_to_datetime
      ).duplicates_by_code
    end

    # Read from the ClickHouse events store, the only one the buckets are ever compared against.
    # An event only moves the compared usage from inside the billing window, so the event
    # timestamps are read over that window, which also keeps the read on the primary key of the
    # table together with the metric codes. The ingestion time then tells whether the event landed
    # while the two runs were going, which a backdated timestamp would never show.
    def events_received_since?(since)
      Clickhouse::EventsEnriched
        .where(
          organization_id: subscription.organization_id,
          external_subscription_id: subscription.external_id,
          code: @compared_codes,
          timestamp: boundaries.charges_from_datetime..boundaries.charges_to_datetime,
          enriched_at: since..
        )
        .exists?
    end

    def organization
      @organization ||= subscription.organization
    end

    def billing_context
      @billing_context ||= Billing::Context.from(subscription:)
    end

    def charges
      @charges ||= subscription.plan.charges.includes(:filters, :billable_metric).to_a
    end

    def charges_by_id
      @charges_by_id ||= charges.index_by(&:id)
    end

    def eligible_charges
      @eligible_charges ||= charges.select { RealtimeUsage.supported_charge?(it) }
    end

    def boundaries
      @boundaries ||= BillingPeriodBoundaries.new(
        from_datetime: date_service.from_datetime,
        to_datetime: date_service.to_datetime,
        charges_from_datetime: date_service.charges_from_datetime,
        charges_to_datetime: date_service.charges_to_datetime,
        issuing_date: date_service.next_end_of_period,
        charges_duration: date_service.charges_duration_in_days,
        timestamp:
      )
    end

    def date_service
      @date_service ||= Subscriptions::DatesService.new_instance(subscription, timestamp, current_usage: true)
    end
  end
end
