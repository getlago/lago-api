# frozen_string_literal: true

module RecurringAggregationSnapshots
  # Snapshots a subscription can reuse from the subscription it upgraded or downgraded from.
  # Loads the previous charges once, and the snapshots of each once, for all charge filters.
  class PreviousSubscriptionSnapshots
    def initialize(subscription)
      @subscription = subscription
      @latest_periods = {}
      @filters_changed = {}
      @bucket_signatures = {}
      @signatures = {}
    end

    # Marker and snapshots of the latest period of the previous charge's bucket that holds the same
    # events, or nil when the aggregation must fall back to a full scan (see FetchService).
    # all_buckets: false loads only that bucket, for a caller reading one.
    def period(charge:, charge_filter:, all_buckets: true)
      return unless subscription.previous_subscription_id

      # Two matching charges would read the same events, but a plan with both is ambiguous enough
      # to pay one full scan rather than guess
      matching_charges = previous_charges.fetch(charge.billable_metric_id, []).select do |previous_charge|
        filters_signature(previous_charge) == filters_signature(charge) &&
          previous_charge.presentation_group_keys_values.sort == charge.presentation_group_keys_values.sort
      end
      return unless matching_charges.one?

      previous_charge = matching_charges.first
      previous_filter = matching_previous_filter(previous_charge, charge, charge_filter)
      return if charge_filter&.persisted? && previous_filter.nil?

      bucket_ids = all_buckets ? [nil, *previous_charge.filters.map(&:id)] : [nil, previous_filter&.id].uniq
      marker, records = latest_period(previous_charge, bucket_ids)
      return if marker.nil? || filters_changed_since?(previous_charge, marker)

      bucket_records = records.fetch(previous_filter&.id, [])
      [marker, bucket_records] unless bucket_records.empty? && regrouped_since?(charge, previous_charge, charge_filter, previous_filter, marker)
    end

    private

    attr_reader :subscription, :signatures

    # Weighted sum stores its breakdowns per presentation group, which only the same keys can read.
    # A discarded charge is skipped, its filters are discarded with it and would no longer tell its buckets apart.
    def previous_charges
      @previous_charges ||= Charge
        .where(
          organization_id: subscription.organization_id,
          id: RecurringAggregationSnapshot.where(organization_id: subscription.organization_id, subscription_id: subscription.previous_subscription_id).distinct.select(:charge_id)
        )
        .includes(filters: {values: :billable_metric_filter})
        .group_by(&:billable_metric_id)
    end

    # Not bounded by from_datetime: an upgrade stamps the termination just after the new start.
    def latest_period(previous_charge, bucket_ids)
      @latest_periods[[previous_charge.id, bucket_ids]] ||= begin
        scope = RecurringAggregationSnapshot.where(
          organization_id: subscription.organization_id,
          subscription_id: subscription.previous_subscription_id,
          charge_id: previous_charge.id
        )
        # One statement reads the marker and the buckets, so a run rewriting the period cannot land in between
        latest_to_datetime = scope.where(charge_filter_id: nil).order(to_datetime: :desc).limit(1).select(:to_datetime)
        records = scope.where(charge_filter_id: bucket_ids).of_period(latest_to_datetime).group_by(&:charge_filter_id)
        marker = records[nil]&.first

        marker ? [marker, records] : []
      end
    end

    # The previous snapshots hold the same events only while the previous charge's filters did not
    # move them. The current filters match them by signature, whenever they were created.
    def filters_changed_since?(previous_charge, marker)
      @filters_changed.fetch(previous_charge.id) do
        @filters_changed[previous_charge.id] = RecurringAggregationSnapshot.filters_changed_since?(
          organization_id: subscription.organization_id, charge_ids: previous_charge.id, watermark: marker.watermark
        )
      end
    end

    # An empty bucket has no row to compare grouping keys with: a previous filter edited since the marker,
    # or grouped on other keys, can regroup units that netted to zero into non-zero groups
    def regrouped_since?(charge, previous_charge, charge_filter, previous_filter, marker)
      previous_filter.present? &&
        (previous_filter.updated_at > marker.watermark ||
          Array(previous_filter.pricing_group_keys).sort != Array(charge_filter.pricing_group_keys).sort ||
          previous_charge.accepts_target_wallet != charge.accepts_target_wallet)
    end

    def matching_previous_filter(previous_charge, charge, charge_filter)
      return unless charge_filter&.persisted?

      signature = bucket_signatures(charge)[charge_filter.id]
      previous_charge.filters.find { bucket_signatures(previous_charge)[it.id] == signature }
    end

    def filters_signature(target_charge)
      signatures[target_charge.id] ||= bucket_signatures(target_charge).values.to_set
    end

    # An event goes to the matching filter of highest precedence: a bucket holds the same events on
    # both charges when its filter and the overlapping filters taking precedence over it are the same
    def bucket_signatures(target_charge)
      @bucket_signatures[target_charge.id] ||= target_charge.filters.to_h do |filter|
        preceding = target_charge.filters.select { preceding_overlap?(it, filter) }
        [filter.id, [filter_signature(filter), preceding.map { filter_signature(it) }.tally]]
      end
    end

    def preceding_overlap?(other, filter)
      values = filter.to_h_with_all_values

      (other.precedence <=> filter.precedence).negative? &&
        other.to_h_with_all_values.all? { |key, other_values| !values.key?(key) || other_values.intersect?(values[key]) }
    end

    def filter_signature(filter)
      filter.to_h.transform_values(&:sort)
    end
  end
end
