# frozen_string_literal: true

module RecurringAggregationSnapshots
  # Runs the per-event pay in advance aggregation of the latest events of the current period twice,
  # once starting from the snapshot of the event group and once scanning the full history, and
  # compares the aggregator results per event and item: a subscription's (charge, charge filter), or a
  # contract's (product, product filter). Nothing is persisted: the aggregation only reads, the fee
  # service is the one caching its result.
  class ComparePayInAdvanceService < BaseService
    Result = BaseResult[:rows, :differences, :compared_items_count, :compared_events_count, :rechecked]

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
      :item_id,
      :billable_metric_code,
      :filter_id,
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

    # One owner: a subscription or a contract
    def initialize(subscription: nil, contract: nil, timestamp: Time.current)
      @subscription = subscription
      @contract = contract
      @timestamp = timestamp

      super
    end

    def call
      result.rechecked = false
      result.compared_items_count = compared_items_count
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

    attr_reader :subscription, :contract, :timestamp

    def owner
      subscription || contract
    end

    def compare
      result.rows = events.flat_map { compare_event(it) }
      result.differences = result.rows.select(&:different?)
    end

    # Resolved as Events::PayInAdvanceService resolves it, so the event reaches the same buckets.
    def compare_event(event)
      Events::PayInAdvanceMeteredItemsResolver.call!(event:).selections.flat_map do |selection|
        next [] unless compared?(selection.metered_item)

        selection.metered_item.pricing_buckets.map do |metered_item|
          build_row(event, metered_item, selection.billing_context)
        end
      end
    end

    # A period persisted or invalidated during the snapshot run leaves its read unknown either way:
    # the row is built again, and a period that keeps moving fails the comparison as inconclusive.
    def build_row(event, metered_item, billing_context, attempts: 2)
      snapshot_read = snapshot_read?(metered_item, billing_context)
      snapshot = RecurringAggregationSnapshots.with_forced_read(true) { aggregate(metered_item, billing_context) }

      if snapshot_read != snapshot_read?(metered_item, billing_context)
        return build_row(event, metered_item, billing_context, attempts: attempts - 1) if attempts > 1

        result.service_failure!(code: "snapshot_period_unsettled", message: "snapshot period changed during the comparison").raise_if_error!
      end

      full_scan = RecurringAggregationSnapshots.with_forced_read(false) { aggregate(metered_item, billing_context) }

      Row.new(
        event_transaction_id: event.transaction_id,
        event_timestamp: event.timestamp,
        item_id: metered_item.billing_segment ? metered_item.invoiceable.id : metered_item.charge_id,
        billable_metric_code: metered_item.billable_metric.code,
        filter_id: metered_item.billing_segment ? metered_item.product_filter&.id : persisted_charge_filter_id(metered_item),
        grouped_by: metered_item.grouped_by_values,
        snapshot_read:,
        snapshot:,
        full_scan:
      )
    end

    def persisted_charge_filter_id(metered_item)
      metered_item.charge_filter.id if metered_item.charge_filter&.persisted?
    end

    def aggregate(metered_item, billing_context)
      Aggregation.from(Charges::PayInAdvanceAggregationService.call!(metered_item:, billing_context:))
    end

    # RecurringAggregationSnapshot.readable?: with a period, the event group starts
    # from its snapshot, or from zero without one. The owner is the subscription or contract the event
    # resolves to, which an upgrade can make another subscription.
    def snapshot_read?(metered_item, billing_context)
      return false unless RecurringAggregationSnapshot.eligible?(metered_item:, billing_context:)

      RecurringAggregationSnapshots::FetchService.call!(
        **RecurringAggregationSnapshot.fetch_arguments(metered_item:, billing_context:)
      ).period.present?
    end

    # The latest events of the period put max_timestamp late in it, where the delta is the largest.
    # events_raw keeps every insert of a re-sent event: the latest one is replayed.
    # Events whose metric field is not present? are left out, as Events::PayInAdvanceService#can_create_fee? bills none.
    def events
      return @events if defined?(@events)
      return @events = [] unless period_started_at

      @events = compared_billable_metrics.uniq(&:code).flat_map do |billable_metric|
        if owner.organization.clickhouse_events_store?
          clickhouse_events(billable_metric)
        else
          postgres_events(billable_metric)
        end
      end
    end

    def postgres_events(billable_metric)
      Event
        .where(
          organization_id: owner.organization_id,
          external_subscription_id: owner.external_id,
          code: billable_metric.code,
          timestamp: period_started_at..timestamp
        )
        .where("COALESCE(events.properties ->> ?, '') !~ ?", billable_metric.field_name, Events::Stores::BaseStore::BLANK_VALUE_PATTERN)
        .where("events.properties -> ? NOT IN ('false', '[]', '{}')", billable_metric.field_name)
        .order(timestamp: :desc, created_at: :desc)
        .limit(EVENTS_PER_BILLABLE_METRIC)
        .map { Events::CommonFactory.new_instance(source: it) }
    end

    # Deduplicated before the limit, so the inserts of one event cannot crowd out the others.
    # An event is a (transaction_id, timestamp) pair, as for the event stores, and its field is read
    # from the latest insert, which replaces the others in events_enriched.
    def clickhouse_events(billable_metric)
      scope = Clickhouse::EventsRaw.where(
        organization_id: owner.organization_id,
        external_subscription_id: owner.external_id,
        code: billable_metric.code,
        timestamp: period_started_at..timestamp
      )
      latest_inserts = scope
        .group(:transaction_id, :timestamp)
        .having("NOT match(argMax(properties[?], ingested_at), ?)", billable_metric.field_name, Events::Stores::BaseStore::BLANK_VALUE_PATTERN)
        # events_raw stringifies JSON false, [] and {}, which the Kafka payload keeps and present? rejects
        .having("argMax(properties[?], ingested_at) NOT IN ('false', '[]', '{}')", billable_metric.field_name)
        .order(timestamp: :desc, transaction_id: :asc)
        .limit(EVENTS_PER_BILLABLE_METRIC)
        .select(:transaction_id, :timestamp, "max(ingested_at)")

      scope
        .where("(transaction_id, timestamp, ingested_at) IN (#{latest_inserts.to_sql})")
        .order(timestamp: :desc, transaction_id: :asc)
        .to_a
        .uniq { [it.transaction_id, it.timestamp] }
        .map { Events::CommonFactory.new_instance(source: it) }
    end

    def compared?(metered_item)
      compared_ids.include?(contract ? metered_item.contract_rate_card&.id : metered_item.charge_id)
    end

    def compared_ids
      @compared_ids ||= (contract ? compared_cards : compared_charges).map(&:id).to_set
    end

    def compared_items_count
      contract ? compared_cards.map { it.rate_card.product_id }.uniq.size : compared_charges.size
    end

    def compared_billable_metrics
      contract ? compared_cards.map { it.rate_card.product.billable_metric } : compared_charges.map(&:billable_metric)
    end

    def compared_charges
      @compared_charges ||= subscription.plan.charges.pay_in_advance.includes(:billable_metric).select do |charge|
        charge.billable_metric.recurring? &&
          charge.billable_metric.payable_in_advance? &&
          RecurringAggregationSnapshot::AGGREGATION_TYPES.include?(charge.billable_metric.aggregation_type)
      end
    end

    # The advance cards of metered products effective at the timestamp, as
    # Events::PayInAdvanceBillingSegmentResolver selects them
    def compared_cards
      @compared_cards ||= effective_cards.select do |card|
        product = card.rate_card.product

        card.rate_card.advance? &&
          product.metered? &&
          product.billable_metric.recurring? &&
          RecurringAggregationSnapshot::AGGREGATION_TYPES.include?(product.billable_metric.aggregation_type)
      end
    end

    def effective_cards
      cards = contract.applied_rate_cards
        .starting_before_contract_end
        .includes(rate_card: [:rates, {product: :billable_metric}])
        .order(:effective_date, :created_at, :id)
        .to_a
      date = timestamp.in_time_zone(contract.customer.applicable_timezone).to_date

      ContractRateCards::SelectEffectiveService.call!(contract_rate_cards: cards, date:).contract_rate_cards
    end

    # A contract's cards each open their own segment: events are read from the earliest one open at
    # the timestamp, the resolver then picks the segment of each event.
    def period_started_at
      return date_service.charges_from_datetime if subscription
      return @period_started_at if defined?(@period_started_at)

      @period_started_at = compared_cards.filter_map do |card|
        next if card.rate_card.rates.empty?

        Billing::RateCards::BuildScheduleService.call!(contract_rate_card: card).schedule.segment_covering(timestamp)&.started_at
      end.min
    end

    def date_service
      @date_service ||= Subscriptions::DatesService.new_instance(subscription, timestamp, current_usage: true)
    end
  end
end
