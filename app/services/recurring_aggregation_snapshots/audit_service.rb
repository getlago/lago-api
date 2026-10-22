# frozen_string_literal: true

module RecurringAggregationSnapshots
  # Compares the snapshots of each closed period with the fees its invoice billed, per
  # (charge, charge filter, group). A side without a row counts as zero: groups without units are
  # stored on neither side.
  class AuditService < BaseService
    Result = BaseResult[:rows, :differences, :periods_without_invoice]

    Row = Data.define(
      :charge_id,
      :charge_filter_id,
      :grouped_by,
      :to_datetime,
      :snapshot_units,
      :fee_units,
      :snapshot_events_count,
      :fee_events_count
    ) do
      def different?
        snapshot_units != fee_units || snapshot_events_count != fee_events_count
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
          compare(period, period_snapshots, fees(period.charge_id, invoice_subscription.invoice_id))
        else
          result.periods_without_invoice << period
        end
      end

      result.differences = result.rows.select(&:different?)
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
          fee_events_count: (fee&.events_count || 0 if with_events_count)
        )
      end
    end

    def snapshots
      RecurringAggregationSnapshot
        .where(organization_id: subscription.organization_id, subscription_id: subscription.id)
        .includes(:billable_metric)
        .order(:to_datetime)
    end

    def invoice_subscription(to_datetime)
      subscription.invoice_subscriptions.where(charges_to_datetime: to_datetime).order(created_at: :desc).first
    end

    def fees(charge_id, invoice_id)
      Fee.where(
        organization_id: subscription.organization_id,
        invoice_id:,
        subscription_id: subscription.id,
        charge_id:,
        pay_in_advance_event_id: nil,
        true_up_parent_fee_id: nil
      )
    end

    # Group values come back from JSON on both sides, the zero-unit marker with nil values
    def key(record)
      [record.charge_filter_id, record.grouped_by.compact.transform_values(&:to_s)]
    end
  end
end
