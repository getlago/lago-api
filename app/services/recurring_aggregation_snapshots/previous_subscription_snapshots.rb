# frozen_string_literal: true

module RecurringAggregationSnapshots
  # Snapshots a subscription can reuse from the subscription it upgraded or downgraded from.
  # Loads the previous charges once, and the snapshots of each once, for all charge filters.
  class PreviousSubscriptionSnapshots
    def initialize(subscription)
      @subscription = subscription
      @latest_periods = {}
      @filters_changed = {}
      @signatures = {}
    end

    # Marker and snapshots of the latest period of the previous charge's bucket that holds the same
    # events, or nil when the aggregation must fall back to a full scan (see FetchService)
    def period(charge:, charge_filter:)
      return unless subscription.previous_subscription_id

      # Two matching charges would read the same events, but a plan with both is ambiguous enough
      # to pay one full scan rather than guess
      matching_charges = previous_charges.fetch(charge.billable_metric_id, [])
        .select { |previous_charge| filters_signature(previous_charge) == filters_signature(charge) }
      return unless matching_charges.one?

      previous_charge = matching_charges.first
      previous_filter = matching_previous_filter(previous_charge, charge_filter)
      return if charge_filter&.persisted? && previous_filter.nil?

      marker, records = latest_period(previous_charge)
      return if marker.nil? || filters_changed_since?(charge, previous_charge, marker)

      [marker, records.fetch(previous_filter&.id, [])]
    end

    private

    attr_reader :subscription, :signatures

    # An event goes to the most specific matching filter: a bucket only holds the same events when
    # both charges have the same filters. A discarded charge is skipped, its filters are discarded
    # with it and would no longer tell its buckets apart.
    def previous_charges
      @previous_charges ||= Charge
        .where(
          organization_id: subscription.organization_id,
          id: RecurringAggregationSnapshot.where(organization_id: subscription.organization_id, subscription_id: subscription.previous_subscription_id).distinct.select(:charge_id)
        )
        .includes(filters: {values: :billable_metric_filter})
        .group_by(&:billable_metric_id)
    end

    # Not bounded by from_datetime: an upgrade stamps the termination just after the new start
    def latest_period(previous_charge)
      @latest_periods[previous_charge.id] ||= begin
        scope = RecurringAggregationSnapshot.where(
          organization_id: subscription.organization_id,
          subscription_id: subscription.previous_subscription_id,
          charge_id: previous_charge.id
        )
        marker = scope.where(charge_filter_id: nil).order(to_datetime: :desc, watermark: :desc).first

        if marker
          [marker, scope.where(to_datetime: marker.to_datetime, watermark: marker.watermark).group_by(&:charge_filter_id)]
        else
          []
        end
      end
    end

    # The previous snapshots hold the same events only while neither charge's filters moved them
    def filters_changed_since?(charge, previous_charge, marker)
      charge_ids = [charge.id, previous_charge.id].uniq

      @filters_changed.fetch(charge_ids) do
        @filters_changed[charge_ids] = RecurringAggregationSnapshot.filters_changed_since?(
          organization_id: subscription.organization_id, charge_ids:, watermark: marker.watermark
        )
      end
    end

    def matching_previous_filter(previous_charge, charge_filter)
      return unless charge_filter&.persisted?

      signature = filter_signature(charge_filter)
      previous_charge.filters.find { filter_signature(it) == signature }
    end

    def filters_signature(target_charge)
      signatures[target_charge.id] ||= target_charge.filters.map { filter_signature(it) }.to_set
    end

    def filter_signature(filter)
      filter.to_h.transform_values(&:sort)
    end
  end
end
