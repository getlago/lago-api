# frozen_string_literal: true

module RecurringAggregationSnapshots
  # Runs the per-event pay in advance aggregation of the latest events of the current period twice,
  # once starting from the snapshot of the event group and once scanning the full history, and
  # compares the aggregator results per (event, charge, charge filter). Nothing is persisted: the
  # aggregation only reads, the fee service is the one caching its result.
  class ComparePayInAdvanceService < BaseService
    Result = BaseResult[:rows, :differences, :compared_charges_count, :compared_events_count, :rechecked]

    EVENTS_PER_BILLABLE_METRIC = 3
    RECHECK_DELAY = 5.seconds

    Aggregation = Data.define(
      :aggregation,
      :count,
      :pay_in_advance_aggregation,
      :full_units_number,
      :current_aggregation,
      :max_aggregation,
      :max_aggregation_with_proration,
      :units_applied
    ) do
      def self.from(result)
        new(**members.index_with { result.public_send(it) })
      end
    end

    Row = Data.define(
      :event_transaction_id,
      :event_timestamp,
      :charge_id,
      :billable_metric_code,
      :charge_filter_id,
      :grouped_by,
      :snapshot_read,
      :snapshot,
      :full_scan
    ) do
      # Without a snapshot both runs scan the full history: a difference there is an event ingested
      # between them, never a snapshot bug.
      def different?
        snapshot_read && snapshot != full_scan
      end
    end

    def initialize(subscription:, timestamp: Time.current)
      @subscription = subscription
      @timestamp = timestamp

      super
    end

    def call
      result.rechecked = false
      result.compared_charges_count = compared_charges.size
      result.compared_events_count = events.size
      compare

      if result.differences.any?
        sleep(RECHECK_DELAY)
        result.rechecked = true
        compare
      end

      result
    rescue BaseService::FailedResult => e
      result.fail_with_error!(e.result.error)
    end

    private

    attr_reader :subscription, :timestamp

    def compare
      result.rows = events.flat_map { compare_event(it) }
      result.differences = result.rows.select(&:different?)
    end

    # Resolved as Events::PayInAdvanceService resolves it, so the event reaches the same buckets.
    def compare_event(event)
      Events::PayInAdvanceMeteredItemsResolver.call!(event:).selections.flat_map do |selection|
        next [] unless compared_charge_ids.include?(selection.metered_item.charge_id)

        selection.metered_item.pricing_buckets.map do |metered_item|
          build_row(event, metered_item, selection.billing_context)
        end
      end
    end

    def build_row(event, metered_item, billing_context)
      snapshot = RecurringAggregationSnapshots.with_forced_read(true) { aggregate(metered_item, billing_context) }
      full_scan = RecurringAggregationSnapshots.with_forced_read(false) { aggregate(metered_item, billing_context) }

      Row.new(
        event_transaction_id: event.transaction_id,
        event_timestamp: event.timestamp,
        charge_id: metered_item.charge_id,
        billable_metric_code: metered_item.billable_metric.code,
        charge_filter_id: metered_item.charge_filter&.persisted? ? metered_item.charge_filter.id : nil,
        grouped_by: metered_item.grouped_by_values,
        snapshot_read: snapshot_read?(metered_item, billing_context),
        snapshot:,
        full_scan:
      )
    end

    def aggregate(metered_item, billing_context)
      Aggregation.from(Charges::PayInAdvanceAggregationService.call!(metered_item:, billing_context:))
    end

    # RecurringAggregationSnapshots::FetchService.readable?: with a period, the event group starts
    # from its snapshot, or from zero without one. The subscription is the one the event resolves
    # to, which an upgrade can make another one.
    def snapshot_read?(metered_item, billing_context)
      return false unless RecurringAggregationSnapshot.eligible?(metered_item:, billing_context:)

      RecurringAggregationSnapshots::FetchService.call!(
        subscription: billing_context.subscription,
        charge: metered_item.charge,
        charge_filter: metered_item.charge_filter,
        grouped_by_keys: metered_item.pricing_group_keys,
        from_datetime: metered_item.boundaries.charges_from_datetime
      ).period.present?
    end

    # The latest events of the period put max_timestamp late in it, where the delta is the largest.
    # events_raw keeps every insert of a re-sent transaction id until it merges: one replay each.
    def events
      @events ||= compared_charges.map { it.billable_metric.code }.uniq.flat_map do |code|
        if subscription.organization.clickhouse_events_store?
          clickhouse_events(code)
        else
          postgres_events(code)
        end
      end
    end

    def postgres_events(code)
      Event
        .where(
          organization_id: subscription.organization_id,
          external_subscription_id: subscription.external_id,
          code:,
          timestamp: date_service.charges_from_datetime..timestamp
        )
        .order(timestamp: :desc, created_at: :desc)
        .limit(EVENTS_PER_BILLABLE_METRIC)
        .map { Events::CommonFactory.new_instance(source: it) }
    end

    def clickhouse_events(code)
      Clickhouse::EventsRaw
        .where(
          organization_id: subscription.organization_id,
          external_subscription_id: subscription.external_id,
          code:,
          timestamp: date_service.charges_from_datetime..timestamp
        )
        .order(timestamp: :desc, ingested_at: :desc)
        .limit(EVENTS_PER_BILLABLE_METRIC * 3)
        .to_a
        .uniq(&:transaction_id)
        .first(EVENTS_PER_BILLABLE_METRIC)
        .map { Events::CommonFactory.new_instance(source: it) }
    end

    def compared_charges
      @compared_charges ||= subscription.plan.charges.pay_in_advance.includes(:billable_metric).select do |charge|
        charge.billable_metric.recurring? &&
          RecurringAggregationSnapshot::AGGREGATION_TYPES.include?(charge.billable_metric.aggregation_type)
      end
    end

    def compared_charge_ids
      @compared_charge_ids ||= compared_charges.map(&:id).to_set
    end

    def date_service
      @date_service ||= Subscriptions::DatesService.new_instance(subscription, timestamp, current_usage: true)
    end
  end
end
