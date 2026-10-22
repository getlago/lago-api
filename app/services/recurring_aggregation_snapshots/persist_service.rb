# frozen_string_literal: true

module RecurringAggregationSnapshots
  class PersistService < BaseService
    Result = BaseResult

    # buckets: one {charge_filter:, values:} per pricing bucket of the charge
    # values: one {grouped_by:, units:, events_count:, presentation_breakdowns:} per group of the bucket
    def initialize(subscription:, charge:, to_datetime:, watermark:, buckets:)
      @subscription = subscription
      @charge = charge
      @to_datetime = to_datetime
      @watermark = watermark
      @buckets = buckets

      super
    end

    def call
      RecurringAggregationSnapshot.transaction do
        # Without it, a run with an older watermark could insert a group a newer run left out
        RecurringAggregationSnapshot.with_advisory_lock(lock_key, transaction: true) do
          # Overlapping runs of the same period: the latest watermark has seen the most events.
          # Checked on the whole charge, as an empty filter leaves no row holding the watermark of its run.
          next if period_snapshots.exists?(["watermark > ?", watermark])

          # A group or filter missing from a later run of the period dropped to zero units
          period_snapshots.delete_all
          RecurringAggregationSnapshot.insert_all(rows, returning: false) if rows.any? # rubocop:disable Rails/SkipsModelValidations
        end
      end

      result
    end

    private

    attr_reader :subscription, :charge, :to_datetime, :watermark, :buckets

    def period_snapshots
      RecurringAggregationSnapshot.where(
        organization_id: subscription.organization_id,
        subscription_id: subscription.id,
        charge_id: charge.id,
        to_datetime:
      )
    end

    def lock_key
      "recurring_aggregation_snapshots_#{subscription.id}_#{charge.id}_#{to_datetime.iso8601(6)}"
    end

    def rows
      @rows ||= buckets.flat_map do |bucket|
        bucket[:values].map do |value|
          {
            organization_id: subscription.organization_id,
            subscription_id: subscription.id,
            charge_id: charge.id,
            charge_filter_id: bucket[:charge_filter]&.id,
            billable_metric_id: charge.billable_metric_id,
            grouped_by: value[:grouped_by] || {},
            to_datetime:,
            watermark:,
            units: value[:units],
            events_count: value[:events_count] || 0,
            presentation_breakdowns: value[:presentation_breakdowns] || []
          }
        end
      end
    end
  end
end
