# frozen_string_literal: true

module RecurringAggregationSnapshots
  # Compares the snapshots of each slice a contract closed with the fees the close operation billed, per
  # (product, product filter, group), as AuditService does for subscriptions. No row links a fee to its
  # slice: the slices of each processed close operation are rebuilt from the schedule, and the slice
  # ending at the snapshot's period picks the operation and its fees. A close that billed no fee leaves
  # the operation without invoice, so its snapshots compare with zero. An adjusted fee needs a
  # subscription, so a contract has none to report apart.
  class ContractAuditService < BaseService
    include AuditComparison

    Result = BaseResult[:rows, :differences, :watermark_gap_rows, :periods_without_invoice]

    Row = Data.define(
      :product_id,
      :product_filter_id,
      :grouped_by,
      :to_datetime,
      :snapshot_units,
      :fee_units,
      :snapshot_events_count,
      :fee_events_count,
      :watermark_gap
    ) do
      def different?
        !watermark_gap && (snapshot_units != fee_units || snapshot_events_count != fee_events_count)
      end
    end

    Period = Data.define(:product_id, :product_filter_id, :to_datetime)
    ClosedSlice = Data.define(:operation, :segment)

    def initialize(contract:)
      @contract = contract

      super
    end

    def call
      result.rows = []
      result.periods_without_invoice = []

      snapshots.group_by { Period.new(product_id: it.product_id, product_filter_id: it.product_filter_id, to_datetime: it.to_datetime) }
        .each do |period, period_snapshots|
          closed_slice = closed_slice(period)

          if closed_slice
            compare(period, period_snapshots, closed_slice)
          else
            result.periods_without_invoice << period
          end
        end

      result.differences = result.rows.select(&:different?)
      result.watermark_gap_rows = result.rows.select(&:watermark_gap)
      result
    end

    private

    attr_reader :contract

    def compare(period, snapshots, closed_slice)
      billable_metric = snapshots.first.billable_metric
      # A weighted sum snapshot has no events count: its read never counts the events of a closed period
      with_events_count = !billable_metric.weighted_sum_agg?

      fees = fees(closed_slice)
      stored = snapshots.index_by { group_key(it.grouped_by) }
      billed = fees.index_by { group_key(it.grouped_by) }
      ingested_late = nil

      (stored.keys | billed.keys).each do |grouped_by|
        snapshot = stored[grouped_by]
        fee = billed[grouped_by]
        snapshot_units = snapshot&.units || 0
        snapshot_events_count = snapshot&.events_count || 0

        row = Row.new(
          product_id: period.product_id,
          product_filter_id: period.product_filter_id,
          grouped_by:,
          to_datetime: period.to_datetime,
          snapshot_units: billed_units(billable_metric, snapshot_units),
          fee_units: fee&.total_aggregated_units || 0,
          snapshot_events_count: (snapshot_events_count if with_events_count),
          fee_events_count: (fee&.events_count || 0 if with_events_count),
          watermark_gap: false
        )

        # Without any fee, no event ingested late can explain the snapshot
        if row.different? && billable_metric.sum_agg? && fees.any?
          ingested_late ||= ingested_after_snapshot(snapshots.first, closed_slice.segment, fees)
          late_units, late_events_count = ingested_late.fetch(grouped_by, [0, 0])

          row = row.with(
            watermark_gap: billed_units(billable_metric, snapshot_units + late_units) == row.fee_units &&
              snapshot_events_count + late_events_count == row.fee_events_count
          )
        end

        result.rows << row
      end
    end

    # The processed close operation whose slices include the one ending at the period. A slice is
    # billed on or after its end, by an operation of one of the contract's cards for that product slice.
    def closed_slice(period)
      close_operations(period).each do |operation|
        segment = BillingOperations::ResolveSegmentsService.call!(operation:).segments
          .find { it.ended_at == period.to_datetime }
        return ClosedSlice.new(operation:, segment:) if segment
      end

      nil
    end

    def close_operations(period)
      rate_cards = RateCard.with_discarded
        .where(organization_id: contract.organization_id, product_id: period.product_id, product_filter_id: period.product_filter_id)
      contract_rate_cards = ContractRateCard.with_discarded
        .where(organization_id: contract.organization_id, contract_id: contract.id, rate_card_id: rate_cards.select(:id))

      BillingOperation
        .where(
          organization_id: contract.organization_id,
          contract_rate_card_id: contract_rate_cards.select(:id),
          action_type: "close_metered_arrears",
          cancelled_at: nil,
          billing_at: period.to_datetime..
        )
        .where.not(processed_at: nil)
        .includes(contract_rate_card: [:terms, {contract: :customer, rate_card: {product: :billable_metric}}])
        .order(:billing_at, :id)
    end

    def fees(closed_slice)
      return [] unless closed_slice.operation.invoice_id

      Fee
        .where(organization_id: contract.organization_id, invoice_id: closed_slice.operation.invoice_id, true_up_parent_fee_id: nil)
        .matching_contract_period(
          contract_rate_card_id: closed_slice.operation.contract_rate_card_id,
          from_datetime: closed_slice.segment.started_at,
          to_datetime: closed_slice.segment.ended_at
        )
        .order(:created_at)
        .to_a
    end

    def ingested_after_snapshot(snapshot, segment, fees)
      store = event_store(snapshot, segment)
      return {} unless store

      ingested_after_watermark(store, watermark: snapshot.watermark, until_time: fees.map(&:created_at).max)
    end

    # Reads the events of the slice's bucket as Fees::ChargeService does, with the filters the product has now
    def event_store(snapshot, segment)
      bucket = Fees::ChargeService::MeteredItem.from_billing_segment(billing_segment: segment).pricing_buckets.first
      return unless bucket

      filters = {}
      filters[:grouped_by] = bucket.pricing_group_keys if bucket.pricing_group_keys.present?
      filters[:matching_filters] = bucket.matching_and_ignored_filters.matching_filters
      filters[:ignored_filters] = bucket.matching_and_ignored_filters.ignored_filters

      store = Events::Stores::StoreFactory.new_instance(
        organization: contract.organization,
        billing_context: Billing::Context.from(contract:),
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
      ContractRecurringAggregationSnapshot
        .where(organization_id: contract.organization_id, contract_id: contract.id)
        .includes(:billable_metric)
        .order(:to_datetime, :product_id, :product_filter_id)
    end
  end
end
