# frozen_string_literal: true

module RecurringAggregationSnapshots
  class PersistService < BaseService
    Result = BaseResult

    # values: one {grouped_by:, units:, events_count:, presentation_breakdowns:} per group of the charge filter
    def initialize(subscription:, charge:, charge_filter:, to_datetime:, watermark:, values:)
      @subscription = subscription
      @charge = charge
      @charge_filter = charge_filter
      @to_datetime = to_datetime
      @watermark = watermark
      @values = values

      super
    end

    def call
      RecurringAggregationSnapshot.transaction do
        # Without it, a run with an older watermark could insert a group a newer run left out
        RecurringAggregationSnapshot.with_advisory_lock(lock_key, transaction: true) do
          # Overlapping runs of the same period: the latest watermark has seen the most events
          next if bucket_snapshots.exists?(["watermark > ?", watermark])

          # A group missing from a later run of the period dropped to zero units
          bucket_snapshots.delete_all
          RecurringAggregationSnapshot.insert_all(rows, returning: false) if values.any? # rubocop:disable Rails/SkipsModelValidations
        end
      end

      result
    end

    private

    attr_reader :subscription, :charge, :charge_filter, :to_datetime, :watermark, :values

    def bucket_snapshots
      RecurringAggregationSnapshot.where(
        organization_id: subscription.organization_id,
        subscription_id: subscription.id,
        charge_id: charge.id,
        charge_filter_id: charge_filter&.id,
        to_datetime:
      )
    end

    def lock_key
      "recurring_aggregation_snapshots_#{subscription.id}_#{charge.id}_#{charge_filter&.id}_#{to_datetime.iso8601(6)}"
    end

    def rows
      values.map do |value|
        {
          organization_id: subscription.organization_id,
          subscription_id: subscription.id,
          charge_id: charge.id,
          charge_filter_id: charge_filter&.id,
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
