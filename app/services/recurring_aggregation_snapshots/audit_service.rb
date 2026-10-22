# frozen_string_literal: true

module RecurringAggregationSnapshots
  # Compares the snapshots of each closed period with the fees its invoice billed, per
  # (charge, charge filter, group). A side without a row counts as zero: groups without units are
  # stored on neither side. A fee whose units or amount were adjusted no longer bills the
  # aggregated values, so its rows are reported apart and never as a difference.
  class AuditService < BaseService
    Result = BaseResult[:rows, :differences, :adjusted_rows, :periods_without_invoice]

    Row = Data.define(
      :charge_id,
      :charge_filter_id,
      :grouped_by,
      :to_datetime,
      :snapshot_units,
      :fee_units,
      :snapshot_events_count,
      :fee_events_count,
      :adjusted
    ) do
      def different?
        !adjusted && (snapshot_units != fee_units || snapshot_events_count != fee_events_count)
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

      snapshots.group_by { Period.new(charge_id: it.charge_id, to_datetime: it.to_datetime) }.each do |period, period_snapshots|
        invoice_subscription = invoice_subscription(period.to_datetime)

        if invoice_subscription
          compare(period, period_snapshots, fees(period_snapshots.first.charge, invoice_subscription.invoice_id, period.to_datetime))
        else
          result.periods_without_invoice << period
        end
      end

      result.differences = result.rows.select(&:different?)
      result.adjusted_rows = result.rows.select(&:adjusted)
      result
    end

    private

    attr_reader :subscription

    def compare(period, snapshots, fees)
      # A weighted sum snapshot has no events count: its read never counts the events of a closed period
      with_events_count = !snapshots.first.billable_metric.weighted_sum_agg?

      stored = snapshots.index_by { key(it) }
      billed = fees.index_by { key(it) }

      (stored.keys | billed.keys).each do |charge_filter_id, grouped_by|
        snapshot = stored[[charge_filter_id, grouped_by]]
        fee = billed[[charge_filter_id, grouped_by]]

        result.rows << Row.new(
          charge_id: period.charge_id,
          charge_filter_id:,
          grouped_by:,
          to_datetime: period.to_datetime,
          snapshot_units: snapshot&.units || 0,
          fee_units: fee&.total_aggregated_units || 0,
          snapshot_events_count: (snapshot&.events_count || 0 if with_events_count),
          fee_events_count: (fee&.events_count || 0 if with_events_count),
          adjusted: adjusted?(fee)
        )
      end
    end

    def snapshots
      RecurringAggregationSnapshot
        .where(organization_id: subscription.organization_id, subscription_id: subscription.id)
        .includes(:billable_metric, :charge)
        .order(:to_datetime)
    end

    def invoice_subscription(to_datetime)
      subscription.invoice_subscriptions.where(charges_to_datetime: to_datetime).order(created_at: :desc).first
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

    def adjusted?(fee)
      fee&.adjusted_fee.present? && !fee.adjusted_fee.adjusted_display_name?
    end

    # Group values come back from JSON on both sides, the zero-unit marker with nil values
    def key(record)
      [record.charge_filter_id, record.grouped_by.compact.transform_values(&:to_s)]
    end
  end
end
