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

    RECENT_EVENTS_WINDOW = 1.minute
    RECHECK_DELAY = 5.seconds

    MATCH = "match"
    MISMATCH = "mismatch"
    DELEGATED_DEFAULT_FILTER = "delegated_default_filter"
    RESENT_TRANSACTION_ID = "resent_transaction_id"

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
      compare

      if (result.differences.any? || result.cutover_risks.any?) && recent_events?
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
      served_charges = RealtimeUsage.with_forced_gate { fetch_served_charges }

      result.rows = []
      result.differences = []
      result.cutover_risks = []
      result.duplicate_events_count = 0
      result.eligible_charges_count = eligible_charges.size
      result.served_charges_count = served_charges.size
      result.declined_reason = served_charges.empty? ? decline_reason : nil
      return if served_charges.empty?

      charge_ids = served_charges.map(&:id)
      events_usage = compute_usage(use_usage_buckets: false, charge_ids:)
      bucket_usage = RealtimeUsage.with_forced_gate { compute_usage(use_usage_buckets: true, charge_ids:) }

      @duplicate_events_by_code = fetch_duplicate_events_by_code(served_charges)

      result.rows = build_rows(bucket_usage:, events_usage:)
      result.differences = result.rows.select(&:mismatch?)
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
      ).usage
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

    def build_rows(bucket_usage:, events_usage:)
      bucket_totals = comparable_totals(bucket_usage)
      events_totals = comparable_totals(events_usage)

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
      return DELEGATED_DEFAULT_FILTER if delegated_default_leaf?(row)
      return MATCH unless row.different?
      return RESENT_TRANSACTION_ID if resent_transaction_id?(row)

      MISMATCH
    end

    # The events store keeps the latest insert of a re-sent transaction id where the stream keeps
    # the first, which moves the units without moving the event count. An equal event count is no
    # proof on its own: the window has to actually hold re-sent ids for that metric, otherwise the
    # most common divergence of all, wrong units over the very same events, would be filed as a
    # cutover risk and dropped from the differences.
    def resent_transaction_id?(row)
      row.bucket_events_count == row.events_events_count &&
        duplicate_events_by_code[row.billable_metric_code].to_i.positive?
    end

    # A charge mixing charge filters with group keys delegates its catch-all bucket for good, so
    # its default leaf is expected to come from the events store on both sides.
    def delegated_default_leaf?(row)
      return false if row.charge_filter_id.present?

      charge = charges_by_id[row.charge_id]
      charge.filters.any? && (charge.pricing_group_keys.present? || charge.filters.any? { it.pricing_group_keys.present? })
    end

    def comparable_totals(usage)
      (usage&.fees || []).each_with_object({}) do |fee, totals|
        next unless eligible_charge_ids.include?(fee.charge_id)

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

    def recent_events?
      RecentEventsService.call!(subscription:, since: RECENT_EVENTS_WINDOW.ago).received
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

    def eligible_charge_ids
      @eligible_charge_ids ||= eligible_charges.map(&:id).to_set
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
