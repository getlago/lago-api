# frozen_string_literal: true

module RecurringAggregationSnapshots
  # Compares the snapshots of each closed period with the fees its invoice billed, per
  # (charge, charge filter, group). A side without a row counts as zero: groups without units are
  # stored on neither side. A fee whose units or amount were adjusted no longer bills the
  # aggregated values, so its rows are reported apart and never as a difference. A sum snapshot
  # stops at its watermark while its fee counts the events ingested up to the invoice run: a leaf
  # that these events explain is reported apart too. A period without the default bucket marker
  # reads as a full scan, so it is reported even when its rows match. A subscription moved to a plan
  # override after its invoice was billed on the parent charge, so its fees are matched there too.
  class AuditService < BaseService
    include AuditComparison

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

      override_filter_ids = override_filter_ids(snapshots, fees)
      stored = snapshots.index_by { key(it) }
      billed = fees.index_by { key(it, override_filter_ids) }
      ingested_late = {}

      (stored.keys | billed.keys).each do |charge_filter_id, grouped_by|
        snapshot = stored[[charge_filter_id, grouped_by]]
        fee = billed[[charge_filter_id, grouped_by]]
        snapshot_units = snapshot&.units || 0
        snapshot_events_count = snapshot&.events_count || 0

        row = Row.new(
          # A fee-only row on a parent filter the override has no copy of stays on the parent charge
          charge_id: (snapshot.nil? && fee.charge_filter_id && fee.charge_filter_id == charge_filter_id) ? fee.charge_id : period.charge_id,
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
          ingested_late[charge_filter_id] ||= ingested_after_snapshot(snapshots.first, charge_filter_id, fees)
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
    def ingested_after_snapshot(snapshot, charge_filter_id, fees)
      store = event_store(snapshot, charge_filter_id)
      return {} unless store

      ingested_after_watermark(store, watermark: snapshot.watermark, until_time: fees.map(&:created_at).max)
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
          charge_id: [charge.id, charge.parent_id].compact,
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

    def adjusted?(fee)
      fee&.adjusted_fee.present? && !fee.adjusted_fee.adjusted_display_name?
    end

    # Maps the parent charge's filters billed by the fees to the live filters of the snapshots' charge
    # with the same values, which the override copied. Many filters have no code to match on. Values
    # shared by several filters on either side are left unmapped, so no fee hides another. A removed
    # filter lost its values with it: it stays unmapped and reported.
    def override_filter_ids(snapshots, fees)
      parent_filter_ids = fees.filter_map { it.charge_filter_id if it.charge_id == snapshots.first.charge.parent_id }
      return {} if parent_filter_ids.empty?

      own_ids = ids_by_values(snapshots.first.charge.filters.ids)
      ids_by_values(parent_filter_ids).each_with_object({}) do |(values, parent_id), ids|
        ids[parent_id] = own_ids[values] if own_ids.key?(values)
      end
    end

    def ids_by_values(charge_filter_ids)
      ChargeFilter.where(id: charge_filter_ids.uniq).includes(values: :billable_metric_filter)
        .group_by { it.to_h.transform_values(&:sort) }
        .filter_map { |values, filters| [values, filters.sole.id] if values.present? && filters.one? }
        .to_h
    end

    def key(record, override_filter_ids = {})
      charge_filter_id = override_filter_ids.fetch(record.charge_filter_id, record.charge_filter_id)
      [charge_filter_id, group_key(record.grouped_by)]
    end
  end
end
