# frozen_string_literal: true

module RecurringAggregationSnapshots
  # Compares the snapshots of each closed period with the fees its invoice billed, per
  # (charge, charge filter, group). A side without a row counts as zero: groups without units are
  # stored on neither side. A fee whose units or amount were adjusted no longer bills the
  # aggregated values, so its rows are reported apart and never as a difference. A sum snapshot
  # stops at its watermark while its fee counts the events ingested up to the invoice run: a leaf
  # that these events explain is reported apart too. A period without the default bucket marker
  # reads as a full scan, so it is reported even when its rows match.
  class AuditService < BaseService
    Result = BaseResult[:rows, :differences, :adjusted_rows, :watermark_gap_rows, :periods_without_invoice, :periods_without_marker]

    Row = Data.define(
      :charge_id,
      :charge_filter_id,
      :grouped_by,
      :to_datetime,
      :snapshot_units,
      :fee_units,
      :snapshot_events_count,
      :fee_events_count,
      :adjusted,
      :watermark_gap
    ) do
      def different?
        !adjusted && !watermark_gap && (snapshot_units != fee_units || snapshot_events_count != fee_events_count)
      end
    end

    Period = Data.define(:charge_id, :to_datetime)

    def initialize(subscription:)
      @subscription = subscription

      super
    end

    def call
      result.rows = []
      result.periods_without_invoice = []
      result.periods_without_marker = []

      snapshots.group_by { Period.new(charge_id: it.charge_id, to_datetime: it.to_datetime) }.each do |period, period_snapshots|
        result.periods_without_marker << period if period_snapshots.none? { it.charge_filter_id.nil? }

        invoice_subscription = invoice_subscription(period.to_datetime)

        if invoice_subscription
          compare(period, period_snapshots, fees(period_snapshots.first.charge, invoice_subscription.invoice_id, period.to_datetime))
        else
          result.periods_without_invoice << period
        end
      end

      result.differences = result.rows.select(&:different?)
      result.adjusted_rows = result.rows.select(&:adjusted)
      result.watermark_gap_rows = result.rows.select(&:watermark_gap)
      result
    end

    private

    attr_reader :subscription

    def compare(period, snapshots, fees)
      billable_metric = snapshots.first.billable_metric
      # A weighted sum snapshot has no events count: its read never counts the events of a closed period
      with_events_count = !billable_metric.weighted_sum_agg?

      stored = snapshots.index_by { key(it) }
      billed = fees.index_by { key(it) }
      ingested_late = {}

      (stored.keys | billed.keys).each do |charge_filter_id, grouped_by|
        snapshot = stored[[charge_filter_id, grouped_by]]
        fee = billed[[charge_filter_id, grouped_by]]
        snapshot_units = snapshot&.units || 0
        snapshot_events_count = snapshot&.events_count || 0

        row = Row.new(
          charge_id: period.charge_id,
          charge_filter_id:,
          grouped_by:,
          to_datetime: period.to_datetime,
          snapshot_units: billed_units(billable_metric, snapshot_units),
          fee_units: fee&.total_aggregated_units || 0,
          snapshot_events_count: (snapshot_events_count if with_events_count),
          fee_events_count: (fee&.events_count || 0 if with_events_count),
          adjusted: adjusted?(fee),
          watermark_gap: false
        )

        # Without any fee, no event ingested late can explain the snapshot
        if row.different? && billable_metric.sum_agg? && fees.any?
          ingested_late[charge_filter_id] ||= ingested_after_watermark(snapshots.first, charge_filter_id, fees)
          late_units, late_events_count = ingested_late[charge_filter_id].fetch(grouped_by, [0, 0])

          row = row.with(
            watermark_gap: billed_units(billable_metric, snapshot_units + late_units) == row.fee_units &&
              snapshot_events_count + late_events_count == row.fee_events_count
          )
        end

        result.rows << row
      end
    end

    # Per group, the units and events count of the period ingested after the snapshot's watermark,
    # up to the creation of its fees
    def ingested_after_watermark(snapshot, charge_filter_id, fees)
      store = event_store(snapshot, charge_filter_id)
      return {} unless store

      until_fees = recurring_sums(store, fees.map(&:created_at).max)
      until_watermark = recurring_sums(store, snapshot.watermark)

      until_fees.to_h do |grouped_by, (units, events_count)|
        units_before, events_count_before = until_watermark.fetch(grouped_by, [0, 0])
        [grouped_by, [units - units_before, events_count - events_count_before]]
      end
    end

    def recurring_sums(store, watermark)
      results = if store.grouped_by.present?
        store.grouped_recurring_sum(watermark:)
      else
        [store.recurring_sum(watermark:)]
      end

      # Blank group values share the null group of the snapshot
      results.each_with_object({}) do |aggregation, sums|
        grouped_by = aggregation.respond_to?(:groups) ? aggregation.groups.compact.transform_values(&:to_s) : {}
        units, events_count = sums.fetch(grouped_by, [0, 0])
        sums[grouped_by] = [units + aggregation.snapshot_value, events_count + aggregation.snapshot_events_count]
      end
    end

    # Reads the events of the bucket as Fees::ChargeService does, with the filters the charge has now
    def event_store(snapshot, charge_filter_id)
      bucket = Fees::ChargeService::Sources::Charge.new(charge: snapshot.charge, boundaries: nil)
        .pricing_buckets
        .find { it.charge_filter&.id == charge_filter_id }
      return unless bucket

      filters = {charge_id: snapshot.charge_id}
      filters[:grouped_by] = bucket.pricing_group_keys if bucket.pricing_group_keys.present?

      if bucket.charge_filter
        filters[:charge_filter] = bucket.charge_filter
        filters[:matching_filters] = bucket.matching_and_ignored_filters.matching_filters
        filters[:ignored_filters] = bucket.matching_and_ignored_filters.ignored_filters
      end

      store = Events::Stores::StoreFactory.new_instance(
        organization: subscription.organization,
        billing_context: Billing::Context.from(subscription:),
        code: snapshot.billable_metric.code,
        boundaries: {to_datetime: snapshot.to_datetime},
        filters:
      )
      store.numeric_property = true
      store.aggregation_property = snapshot.billable_metric.field_name
      store.use_from_boundary = false
      store
    end

    def snapshots
      RecurringAggregationSnapshot
        .where(organization_id: subscription.organization_id, subscription_id: subscription.id)
        .includes(:billable_metric, :charge)
        .order(:to_datetime)
    end

    def invoice_subscription(to_datetime)
      # Advance charges and pay in advance invoices can share the boundary of the period
      subscription.invoice_subscriptions
        .where(charges_to_datetime: to_datetime, invoicing_reason: %i[subscription_periodic subscription_terminating])
        .order(created_at: :desc)
        .first
    end

    def fees(charge, invoice_id, to_datetime)
      scope = Fee
        .where(
          organization_id: subscription.organization_id,
          subscription_id: subscription.id,
          charge_id: charge.id,
          pay_in_advance_event_id: nil,
          true_up_parent_fee_id: nil
        )
        .includes(:adjusted_fee)
        .order(:created_at)

      if charge.invoiceable?
        scope.where(invoice_id:)
      else
        # Non-invoiceable fees are created without the period's invoice and may be attached to another one later
        scope.where("(fees.properties->>'charges_to_datetime')::timestamptz = ?", to_datetime.iso8601(3))
      end
    end

    # A sum fee bills its units rounded and clamped at zero (see Fees::ChargeService#init_fee),
    # a weighted sum fee keeps them raw in total_aggregated_units
    def billed_units(billable_metric, units)
      if billable_metric.weighted_sum_agg?
        units
      else
        [BillableMetrics::Aggregations::ApplyRoundingService.call!(billable_metric:, units:).units, 0].max
      end
    end

    def adjusted?(fee)
      fee&.adjusted_fee.present? && !fee.adjusted_fee.adjusted_display_name?
    end

    # Group values come back from JSON on both sides, the zero-unit marker with nil values
    def key(record)
      [record.charge_filter_id, record.grouped_by.compact.transform_values(&:to_s)]
    end
  end
end
