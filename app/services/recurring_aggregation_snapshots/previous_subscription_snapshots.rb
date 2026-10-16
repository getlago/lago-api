# frozen_string_literal: true

module RecurringAggregationSnapshots
  # Snapshots a subscription can reuse from the subscription it upgraded or downgraded from.
  # Loads the previous charges once, and the snapshots of each once, for all charge filters.
  class PreviousSubscriptionSnapshots
    def initialize(subscription)
      @subscription = subscription
      @latest_records = {}
      @signatures = {}
    end

    # Latest snapshots of the previous charge's bucket that holds the same events, or [] when
    # the aggregation must fall back to a full scan
    def records(charge:, charge_filter:)
      return [] unless subscription.previous_subscription_id

      # Two matching charges would read the same events, but a plan with both is ambiguous enough
      # to pay one full scan rather than guess
      matching_charges = previous_charges.fetch(charge.billable_metric_id, [])
        .select { |previous_charge| filters_signature(previous_charge) == filters_signature(charge) }
      return [] unless matching_charges.one?

      previous_charge = matching_charges.first
      return latest_records(previous_charge).fetch(nil, []) unless charge_filter&.persisted?

      signature = filter_signature(charge_filter)
      previous_filter = previous_charge.filters.find { filter_signature(it) == signature }
      return [] unless previous_filter

      latest_records(previous_charge).fetch(previous_filter.id, [])
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
          id: RecurringAggregationSnapshot.where(subscription_id: subscription.previous_subscription_id).distinct.select(:charge_id)
        )
        .includes(filters: {values: :billable_metric_filter})
        .group_by(&:billable_metric_id)
    end

    # Snapshots of the latest period of each charge filter, by charge filter id
    def latest_records(previous_charge)
      @latest_records[previous_charge.id] ||= begin
        ranked = RecurringAggregationSnapshot
          .where(subscription_id: subscription.previous_subscription_id, charge_id: previous_charge.id)
          .select("recurring_aggregation_snapshots.*, RANK() OVER (PARTITION BY charge_filter_id ORDER BY to_datetime DESC) AS period_rank")

        RecurringAggregationSnapshot
          .from(ranked, :recurring_aggregation_snapshots)
          .where("period_rank = 1")
          .group_by(&:charge_filter_id)
      end
    end

    def filters_signature(target_charge)
      signatures[target_charge.id] ||= target_charge.filters.map { filter_signature(it) }.to_set
    end

    def filter_signature(filter)
      filter.to_h.transform_values(&:sort)
    end
  end
end
