# frozen_string_literal: true

module RecurringAggregationSnapshots
  # Snapshots of a subscription's charge: one bucket per charge filter, plus the default bucket that marks the period.
  SubscriptionKey = Data.define(:subscription, :charge) do
    def model
      RecurringAggregationSnapshot
    end

    delegate :organization_id, to: :subscription

    def snapshots
      model.where(organization_id:, subscription_id: subscription.id, charge_id: charge.id)
    end

    # filter_ids: the buckets to load besides the default one, every filter of the charge when nil
    def bucket_ids(filter_ids)
      [nil, *(filter_ids || charge.filters.ids)]
    end

    def marker_bucket_id
      nil
    end

    def bucket_id(filter)
      filter&.id
    end

    def row_attributes
      {organization_id:, subscription_id: subscription.id, charge_id: charge.id, billable_metric_id: charge.billable_metric_id}
    end

    def lock_key(to_datetime)
      "recurring-aggregation-snapshot-#{subscription.id}-#{charge.id}-#{to_datetime.iso8601(6)}"
    end

    def filters_changed_since?(watermark)
      model.filters_changed_since?(organization_id:, charge_ids: charge.id, watermark:)
    end

    # An upgrade or downgrade keeps the external id, so the events counted by the previous
    # subscription are the ones this one reads.
    def previous_period(filter:, all_buckets:, grouped_by_values:, grouped_by_keys:)
      subscription.previous_recurring_aggregation_snapshots.period(
        charge:, charge_filter: filter, all_buckets:, grouped_by_values:, grouped_by_keys:
      )
    end
  end
end
