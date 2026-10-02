# frozen_string_literal: true

module RecurringAggregationSnapshots
  class PersistService < BaseService
    Result = BaseResult

    # values: one {grouped_by:, units:} per group of the charge filter, zero units included
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
      if values.any?
        # Overlapping runs of the same period: the latest watermark has seen the most events
        RecurringAggregationSnapshot.upsert_all( # rubocop:disable Rails/SkipsModelValidations
          rows,
          unique_by: :idx_recurring_aggregation_snapshots_unique,
          on_duplicate: Arel.sql(<<~SQL.squish),
            units = EXCLUDED.units, watermark = EXCLUDED.watermark, updated_at = CURRENT_TIMESTAMP
            WHERE recurring_aggregation_snapshots.watermark <= EXCLUDED.watermark
          SQL
          returning: false
        )
      end

      result
    end

    private

    attr_reader :subscription, :charge, :charge_filter, :to_datetime, :watermark, :values

    def rows
      values.map do |value|
        {
          organization_id: subscription.organization_id,
          subscription_id: subscription.id,
          charge_id: charge.id,
          charge_filter_id:,
          billable_metric_id: charge.billable_metric_id,
          grouped_by: value[:grouped_by] || {},
          to_datetime:,
          watermark:,
          units: value[:units]
        }
      end
    end

    # The default bucket of a charge with filters is an unsaved ChargeFilter
    def charge_filter_id
      charge_filter&.persisted? ? charge_filter.id : nil
    end
  end
end
