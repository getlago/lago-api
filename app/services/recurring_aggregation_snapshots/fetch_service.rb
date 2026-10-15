# frozen_string_literal: true

module RecurringAggregationSnapshots
  class FetchService < BaseService
    Snapshot = Data.define(:grouped_by, :units, :events_count, :presentation_breakdowns, :to_datetime, :watermark) do
      def initialize(presentation_breakdowns: [], **)
        super
      end
    end

    Result = BaseResult[:snapshots]

    def initialize(subscription:, charge:, charge_filter:, grouped_by_keys:, from_datetime:)
      @subscription = subscription
      @charge = charge
      @charge_filter = charge_filter
      @grouped_by_keys = grouped_by_keys
      @from_datetime = from_datetime

      super
    end

    # Returns the snapshots of the latest period closed before from_datetime, one per group,
    # or nil when the aggregation must fall back to a full scan.
    def call
      records = latest_records(own_snapshots).to_a
      records = previous_subscription_records if records.empty?

      result.snapshots = if records.any? && records.all? { |record| same_grouped_by_keys?(record) }
        records.map { |record| to_snapshot(record) }
      end

      result
    end

    private

    attr_reader :subscription, :charge, :charge_filter, :grouped_by_keys, :from_datetime

    def own_snapshots
      RecurringAggregationSnapshot.where(
        subscription_id: subscription.id,
        charge_id: charge.id,
        charge_filter_id: default_bucket? ? nil : charge_filter.id
      ).where(to_datetime: ...from_datetime)
    end

    def latest_records(scope)
      scope.where(to_datetime: scope.select("MAX(to_datetime)"))
    end

    # An upgrade or downgrade keeps the external id, so the events counted by the previous
    # subscription are the ones this one reads. Its snapshots close at the termination, which an
    # upgrade stamps just after this subscription starts: they are not bounded by from_datetime.
    def previous_subscription_records
      return [] unless subscription.previous_subscription_id

      # Two matching charges would read the same events, but a plan with both is ambiguous enough
      # to pay one full scan rather than guess
      matching_charges = previous_charges
      return [] unless matching_charges.one?

      previous_charge = matching_charges.first
      previous_filter = matching_previous_filter(previous_charge)
      return [] if !default_bucket? && previous_filter.nil?

      latest_records(
        RecurringAggregationSnapshot.where(
          subscription_id: subscription.previous_subscription_id,
          charge_id: previous_charge.id,
          charge_filter_id: previous_filter&.id
        )
      ).to_a
    end

    # An event goes to the most specific matching filter: a bucket only holds the same events when
    # both charges have the same filters. A discarded charge is skipped, its filters are discarded
    # with it and would no longer tell its buckets apart.
    def previous_charges
      charge_ids = RecurringAggregationSnapshot
        .where(subscription_id: subscription.previous_subscription_id, billable_metric_id: charge.billable_metric_id)
        .distinct
        .select(:charge_id)

      Charge
        .where(organization_id: subscription.organization_id, id: charge_ids)
        .includes(filters: {values: :billable_metric_filter})
        .select { |previous_charge| filters_signature(previous_charge) == filters_signature(charge) }
    end

    def matching_previous_filter(previous_charge)
      return if default_bucket?

      previous_charge.filters.find { filter_signature(it) == filter_signature(charge_filter) }
    end

    def filters_signature(target_charge)
      target_charge.filters.map { filter_signature(it) }.to_set
    end

    def filter_signature(filter)
      filter.to_h.transform_values(&:sort)
    end

    def default_bucket?
      !charge_filter&.persisted?
    end

    # Snapshots grouped on other keys cannot be regrouped, only a full scan can
    def same_grouped_by_keys?(record)
      record.grouped_by.keys.sort == Array(grouped_by_keys).map(&:to_s).sort
    end

    def to_snapshot(record)
      Snapshot.new(
        grouped_by: record.grouped_by.freeze,
        units: record.units,
        events_count: record.events_count,
        presentation_breakdowns: record.presentation_breakdowns.map { it.symbolize_keys.freeze }.freeze,
        to_datetime: record.to_datetime,
        watermark: record.watermark
      )
    end
  end
end
