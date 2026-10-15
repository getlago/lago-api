# frozen_string_literal: true

require "rails_helper"

RSpec.describe BillableMetrics::Aggregations::SumService, transaction: false do
  subject(:sum_service) do
    described_class.new(
      event_store:,
      metered_item:,
      billing_context:,
      boundaries:,
      filters:,
      bypass_aggregation:
    )
  end

  let(:event_store_class) { Events::Stores::PostgresStore }
  let(:metered_item) do
    Fees::ChargeService::MeteredItem.from_charge(
      charge:,
      boundaries: BillingPeriodBoundaries.new(
        from_datetime:,
        to_datetime:,
        charges_from_datetime: from_datetime,
        charges_to_datetime: to_datetime,
        charges_duration: (to_datetime.to_date - from_datetime.to_date).to_i + 1,
        timestamp: to_datetime
      )
    )
  end
  let(:boundaries) { {from_datetime:, to_datetime:} }
  let(:billing_context) { Billing::Context.from(subscription:) }
  let(:event_store) do
    event_store_class.new(code: billable_metric.code, billing_context:, boundaries:, filters:)
  end
  let(:bypass_aggregation) { false }
  let(:filters) do
    {event: pay_in_advance_event, grouped_by:, presentation_by:, charge_filter:, matching_filters:, ignored_filters:}
  end

  let(:subscription) { create(:subscription, started_at: Time.current.beginning_of_month - 6.months) }
  let(:organization) { subscription.organization }
  let(:customer) { subscription.customer }
  let(:grouped_by) { nil }
  let(:presentation_by) { nil }
  let(:charge_filter) { nil }
  let(:matching_filters) { nil }
  let(:ignored_filters) { nil }

  let(:billable_metric) do
    create(
      :billable_metric,
      organization:,
      aggregation_type: "sum_agg",
      field_name: "total_count"
    )
  end

  let(:charge) do
    create(
      :standard_charge,
      billable_metric:
    )
  end

  let(:from_datetime) { subscription.started_at + 5.months }
  let(:to_datetime) { subscription.started_at + 6.months }
  let(:pay_in_advance_event) { nil }
  let(:options) do
    {free_units_per_events: 2, free_units_per_total_aggregation: 30}
  end

  let(:old_events) do
    create_list(
      :event,
      2,
      organization_id: organization.id,
      code: billable_metric.code,
      customer:,
      subscription:,
      timestamp: subscription.started_at + 3.months,
      properties: {
        total_count: 2.5
      }
    )
  end

  let(:latest_events) do
    create_list(
      :event,
      4,
      organization_id: organization.id,
      code: billable_metric.code,
      customer:,
      subscription:,
      timestamp: to_datetime - 1.day,
      properties: {
        total_count: 12
      }
    )
  end

  before do
    old_events
    latest_events
  end

  it "aggregates the events" do
    result = sum_service.aggregate(options:)

    expect(result.aggregation).to eq(48)
    expect(result.pay_in_advance_aggregation).to be_zero
    expect(result.count).to eq(4)
    expect(result.options).to eq({running_total: [12, 24]})
  end

  context "when billable metric is recurring" do
    before { billable_metric.update!(recurring: true) }

    it "aggregates the events" do
      result = sum_service.aggregate(options:)

      expect(result.aggregation).to eq(53)
      expect(result.pay_in_advance_aggregation).to be_zero
      expect(result.count).to eq(6)
      expect(result.options).to eq({running_total: [2.5, 5]})
    end

    context "with a recurring watermark" do
      let(:options) { {recurring_watermark: Time.current + 1.minute} }

      before do
        create(:event, organization_id: organization.id, code: billable_metric.code, customer:, subscription:,
          timestamp: to_datetime - 2.days, created_at: Time.current + 1.hour, properties: {total_count: 7})
      end

      it "only counts the events ingested up to the watermark in the recurring units" do
        result = sum_service.aggregate(options:)

        expect(result.aggregation).to eq(60)
        expect(result.count).to eq(7)
        expect(result.recurring_units).to eq(53)
        expect(result.recurring_events_count).to eq(6)
      end
    end
  end

  describe "recurring snapshots" do
    let(:old_events) { nil }
    let(:latest_events) { nil }
    let(:billable_metric) { create(:sum_billable_metric, :recurring, organization:, field_name: "total_count") }
    let(:periods) do
      Array.new(3) do |index|
        from = subscription.started_at + (index + 1).months
        from..(from + 1.month - 1.second)
      end
    end

    def watermark(period)
      period.end + 1.hour
    end

    def create_event(timestamp:, value:, region:, created_at: timestamp)
      create(:event, organization_id: organization.id, code: billable_metric.code, customer:, subscription:,
        timestamp:, created_at:, properties: {total_count: value, region:})
    end

    def aggregate(period, initial_value:, initial_period: nil, options: {})
      period_boundaries = {from_datetime: period.begin, to_datetime: period.end}
      store = event_store_class.new(code: billable_metric.code, billing_context:, boundaries: period_boundaries, filters:)

      described_class.new(event_store: store, metered_item:, billing_context:, boundaries: period_boundaries, filters:, initial_value:, initial_period:)
        .aggregate(options: {recurring_watermark: watermark(period)}.merge(options))
    end

    def closed(period)
      RecurringAggregationSnapshots::FetchService::Period.new(to_datetime: period.end, watermark: watermark(period))
    end

    # As persisted: a group without units nor events has no snapshot
    def snapshots(period, aggregation_results)
      aggregation_results
        .reject { it.recurring_units.zero? && it.recurring_events_count.zero? }
        .map { snapshot(period, it) }
    end

    def snapshot(period, aggregation_result)
      RecurringAggregationSnapshots::FetchService::Snapshot.new(
        grouped_by: aggregation_result.grouped_by || {},
        units: aggregation_result.recurring_units,
        events_count: aggregation_result.recurring_events_count,
        to_datetime: period.end,
        watermark: watermark(period)
      )
    end

    def totals(aggregation_result)
      [
        aggregation_result.grouped_by,
        aggregation_result.aggregation,
        aggregation_result.count,
        aggregation_result.recurring_units,
        aggregation_result.recurring_events_count
      ]
    end

    before do
      create_event(timestamp: subscription.started_at + 1.day, value: 3, region: "us")
      periods.each_with_index do |period, index|
        create_event(timestamp: period.begin + 1.day, value: 10 * (index + 1), region: "eu")
      end
      create_event(timestamp: periods.last.begin + 2.days, value: 4, region: "apac")

      # Dated in the first period, ingested after its snapshot
      create_event(timestamp: periods.first.begin + 2.days, created_at: watermark(periods.first) + 1.minute, value: 7, region: "eu")
    end

    it "matches the full scan from one period to the next" do
      initial_value = initial_period = nil

      periods.each do |period|
        full_scan = aggregate(period, initial_value: nil)
        from_snapshot = aggregate(period, initial_value:, initial_period:)

        expect(totals(from_snapshot)).to eq(totals(full_scan))
        initial_value, initial_period = snapshots(period, [from_snapshot]), closed(period)
      end

      expect(totals(aggregate(periods.last, initial_value: nil))).to eq([nil, 74, 6, 74, 6])
    end

    it "adds the events the snapshot did not count to its units" do
      initial_value = [snapshot(periods.first, aggregate(periods.first, initial_value: nil)).with(units: 1000)]

      result = aggregate(periods.second, initial_value:, initial_period: closed(periods.first))

      expect(result.aggregation).to eq(1000 + 7 + 20)
    end

    context "when the bucket had no usage at the end of the previous period" do
      it "starts from zero and only reads the events the period did not count" do
        result = aggregate(periods.second, initial_value: [], initial_period: closed(periods.first))

        expect(totals(result)).to eq([nil, 7 + 20, 2, 7 + 20, 2])
      end

      context "with a filter matching events of the last period only" do
        let(:matching_filters) { {"region" => ["apac"]} }

        it "matches the full scan from one period to the next" do
          initial_value = initial_period = nil

          periods.each do |period|
            full_scan = aggregate(period, initial_value: nil)
            from_snapshot = aggregate(period, initial_value:, initial_period:)

            expect(totals(from_snapshot)).to eq(totals(full_scan))
            initial_value, initial_period = snapshots(period, [from_snapshot]), closed(period)
          end

          expect(totals(aggregate(periods.last, initial_value: nil))).to eq([nil, 4, 1, 4, 1])
        end
      end
    end

    context "with pricing group keys" do
      let(:grouped_by) { %w[region] }

      it "matches the full scan from one period to the next" do
        initial_value = initial_period = nil

        periods.each do |period|
          full_scan = aggregate(period, initial_value: nil)
          from_snapshot = aggregate(period, initial_value:, initial_period:)

          expect(from_snapshot.aggregations.map { totals(it) }).to match_array(full_scan.aggregations.map { totals(it) })
          initial_value, initial_period = snapshots(period, from_snapshot.aggregations), closed(period)
        end

        expect(aggregate(periods.last, initial_value: nil).aggregations.map { totals(it) }).to match_array([
          [{"region" => "us"}, 3, 1, 3, 1],
          [{"region" => "eu"}, 67, 4, 67, 4],
          [{"region" => "apac"}, 4, 1, 4, 1]
        ])
      end
    end

    context "when no group had usage at the end of the previous period" do
      let(:grouped_by) { %w[region] }

      it "starts every group from zero and only reads the events the period did not count" do
        result = aggregate(periods.second, initial_value: [], initial_period: closed(periods.first))

        expect(result.aggregations.map { totals(it) }).to eq([[{"region" => "eu"}, 7 + 20, 2, 7 + 20, 2]])
      end

      context "with a missing and a blank group value in the period" do
        before do
          create_event(timestamp: periods.second.begin + 3.days, value: 5, region: nil)
          create_event(timestamp: periods.second.begin + 4.days, value: 3, region: " ")
        end

        it "counts both in the null group" do
          result = aggregate(periods.second, initial_value: [], initial_period: closed(periods.first))
          null_groups = result.aggregations.select { it.grouped_by == {"region" => nil} }
          full_scan_null_groups = aggregate(periods.second, initial_value: nil).aggregations.select { it.grouped_by == {"region" => nil} }

          expect(full_scan_null_groups.sum(&:aggregation)).to eq(8)
          expect(null_groups.sum(&:aggregation)).to eq(8)
          expect(null_groups.sum(&:count)).to eq(2)
        end
      end
    end

    context "when the charge is paid in advance" do
      let(:initial_value) { [snapshot(periods.first, aggregate(periods.first, initial_value: nil)).with(units: 1000)] }

      it "adds the events the snapshot did not count to its units" do
        result = aggregate(periods.second, initial_value:, initial_period: closed(periods.first), options: {is_pay_in_advance: true})

        expect(result.aggregation).to eq(1000 + 7 + 20)
      end

      it "reads the current usage from the snapshot" do
        result = aggregate(periods.second, initial_value:, options: {recurring_watermark: nil, is_pay_in_advance: true, is_current_usage: true})

        expect(result.current_usage_units).to eq(1000 + 7 + 20)
      end
    end

    context "with current usage" do
      let(:initial_value) { [snapshot(periods.first, aggregate(periods.first, initial_value: nil)).with(units: 1000)] }
      let(:options) { {recurring_watermark: nil, is_current_usage: true} }

      it "adds the events the snapshot did not count" do
        result = aggregate(periods.second, initial_value:, initial_period: closed(periods.first), options:)

        expect(result.aggregation).to eq(1000 + 7 + 20)
      end

      context "when the store answers the sum incrementally" do
        before do
          allow(event_store_class).to receive(:new).and_wrap_original do |original, **args|
            original.call(**args).tap { allow(it).to receive(:incremental_sum?).and_return(true) }
          end
        end

        it "ignores the snapshot" do
          result = aggregate(periods.second, initial_value:, initial_period: closed(periods.first), options:)

          expect(result.aggregation).to eq(40)
        end
      end
    end
  end

  context "when a precomputed aggregation is passed" do
    let(:precomputed_aggregation) { Events::Stores::BaseStore::AggregationResult.new(value: 999, events_count: 7) }

    it "uses it instead of querying the event store" do
      result = sum_service.aggregate(options: {precomputed_aggregation:})

      expect(result.aggregation).to eq(999)
      expect(result.count).to eq(7)
    end
  end

  context "when precomputed grouped aggregations are passed" do
    let(:grouped_by) { %w[region] }
    let(:precomputed_grouped_aggregations) do
      [
        Events::Stores::BaseStore::GroupedAggregationResult.new(groups: {"region" => "us"}, value: 100, events_count: 3),
        Events::Stores::BaseStore::GroupedAggregationResult.new(groups: {"region" => "eu"}, value: 50, events_count: 2)
      ]
    end

    it "builds the group results from them" do
      result = sum_service.aggregate(options: {precomputed_grouped_aggregations:})

      expect(result.aggregations.map { |agg| [agg.grouped_by, agg.aggregation, agg.count] }).to match_array(
        [
          [{"region" => "us"}, 100, 3],
          [{"region" => "eu"}, 50, 2]
        ]
      )
    end

    context "when they are blank" do
      let(:precomputed_grouped_aggregations) { [] }

      it "returns empty results" do
        result = sum_service.aggregate(options: {precomputed_grouped_aggregations:})

        expect(result.aggregations.map(&:aggregation)).to eq([0])
      end
    end
  end

  context "when options are not present" do
    let(:options) { {} }

    it "returns an empty running total array" do
      result = sum_service.aggregate(options:)
      expect(result.options).to eq({running_total: []})
    end
  end

  context "when option values are nil" do
    let(:options) do
      {free_units_per_events: nil, free_units_per_total_aggregation: nil}
    end

    it "returns an empty running total array" do
      result = sum_service.aggregate(options:)
      expect(result.options).to eq({running_total: []})
    end
  end

  context "when free_units_per_events is nil" do
    let(:options) do
      {free_units_per_events: nil, free_units_per_total_aggregation: 30}
    end

    it "returns running total based on per total aggregation" do
      result = sum_service.aggregate(options:)
      expect(result.options).to eq({running_total: [12, 24, 36]})
    end
  end

  context "when free_units_per_total_aggregation is nil" do
    let(:options) do
      {free_units_per_events: 2, free_units_per_total_aggregation: nil}
    end

    it "returns running total based on per events" do
      result = sum_service.aggregate(options:)
      expect(result.options).to eq({running_total: [12, 24]})
    end
  end

  context "when charge is dynamic" do
    let(:charge) { create(:dynamic_charge, billable_metric:) }

    it "computes the precise_total_amount_cents" do
      result = sum_service.aggregate(options:)
      expect(result.precise_total_amount_cents).to be_zero
    end

    context "with events that specify a precise_total_amount_cents" do
      let(:old_events) do
        create_list(
          :event,
          2,
          organization_id: organization.id,
          code: billable_metric.code,
          customer:,
          subscription:,
          timestamp: subscription.started_at + 3.months,
          properties: {
            total_count: 2.5
          },
          precise_total_amount_cents: 12
        )
      end
      let(:latest_events) do
        create_list(
          :event,
          4,
          organization_id: organization.id,
          code: billable_metric.code,
          customer:,
          subscription:,
          timestamp: to_datetime - 1.day,
          properties: {
            total_count: 12
          },
          precise_total_amount_cents: 10
        )
      end

      it "computes the precise_total_amount_cents" do
        result = sum_service.aggregate(options:)
        expect(result.aggregation).to eq(4 * 12)
        expect(result.precise_total_amount_cents).to eq(4 * 10)
      end
    end

    context "when filters are given" do
      let(:matching_filters) { {region: ["europe"]} }

      before do
        create(
          :event,
          organization_id: organization.id,
          code: billable_metric.code,
          customer:,
          subscription:,
          timestamp: to_datetime - 1.day,
          properties: {
            total_count: 12,
            region: "europe"
          },
          precise_total_amount_cents: 5
        )

        create(
          :event,
          organization_id: organization.id,
          code: billable_metric.code,
          customer:,
          subscription:,
          timestamp: to_datetime - 12.hours,
          properties: {
            total_count: 8,
            region: "europe"
          },
          precise_total_amount_cents: 7
        )

        create(
          :event,
          organization_id: organization.id,
          code: billable_metric.code,
          customer:,
          subscription:,
          timestamp: to_datetime - 1.day,
          properties: {
            total_count: 12,
            region: "africa"
          },
          precise_total_amount_cents: 9
        )
      end

      it "aggregates the events matching the filter" do
        result = sum_service.aggregate(options:)

        expect(result.aggregation).to eq(20)
        expect(result.count).to eq(2)
        expect(result.precise_total_amount_cents).to eq(12)
        expect(result.options).to eq({running_total: [12, 20]})
      end
    end
  end

  context "when events are out of bounds" do
    let(:latest_events) do
      create_list(
        :event,
        4,
        organization_id: organization.id,
        code: billable_metric.code,
        customer:,
        subscription:,
        timestamp: to_datetime + 1.day,
        properties: {
          total_count: 12
        }
      )
    end

    it "does not take events into account" do
      result = sum_service.aggregate

      expect(result.aggregation).to eq(0)
      expect(result.count).to eq(0)
      expect(result.options).to eq({running_total: []})
    end
  end

  context "when properties is not found on events" do
    before do
      billable_metric.update!(field_name: "foo_bar")
    end

    it "counts as zero" do
      result = sum_service.aggregate

      expect(result.aggregation).to eq(0)
      expect(result.count).to eq(0)
      expect(result.options).to eq({running_total: []})
    end
  end

  context "when properties is a float" do
    before do
      create(
        :event,
        organization_id: organization.id,
        code: billable_metric.code,
        customer:,
        subscription:,
        timestamp: to_datetime - 1.day,
        properties: {
          total_count: 4.5
        }
      )
    end

    it "aggregates the events" do
      result = sum_service.aggregate

      expect(result.aggregation).to eq(52.5)
    end
  end

  context "when properties is not a number" do
    before do
      create(
        :event,
        organization_id: organization.id,
        code: billable_metric.code,
        customer:,
        subscription:,
        timestamp: to_datetime - 1.day,
        properties: {
          total_count: "foo_bar"
        }
      )
    end

    it "ignores the event" do
      result = sum_service.aggregate

      expect(result).to be_success
      expect(result.aggregation).to eq(48)
      expect(result.count).to eq(4)
    end
  end

  context "when current usage context and charge is pay in advance" do
    let(:options) do
      {is_pay_in_advance: true, is_current_usage: true}
    end

    let(:latest_events) do
      create(
        :event,
        organization_id: organization.id,
        code: billable_metric.code,
        customer:,
        subscription:,
        timestamp: to_datetime - 3.days,
        properties: {
          total_count: 4
        }
      )
    end

    let(:cached_aggregation) do
      create(
        :cached_aggregation,
        organization:,
        charge:,
        event_transaction_id: latest_events.transaction_id,
        external_subscription_id: subscription.external_id,
        timestamp: to_datetime - 3.days,
        current_aggregation: "4",
        max_aggregation: "6"
      )
    end

    before do
      billable_metric.update!(recurring: true)
      cached_aggregation
    end

    it "returns period maximum as aggregation" do
      result = sum_service.aggregate(options:)

      expect(result.aggregation).to eq(11)
    end

    context "when cached aggregation does not exist" do
      let(:latest_events) { nil }
      let(:cached_aggregation) { nil }

      before { billable_metric.update!(recurring: false) }

      it "returns zero as aggregation" do
        result = sum_service.aggregate(options:)

        expect(result.aggregation).to eq(0)
      end
    end
  end

  context "with non persisted event" do
    let(:options) do
      {free_units_per_events: 4, free_units_per_total_aggregation: 30, is_pay_in_advance: true}
    end

    let(:latest_events) do
      create_list(
        :event,
        2,
        organization_id: organization.id,
        code: billable_metric.code,
        customer:,
        subscription:,
        timestamp: to_datetime - 1.day,
        properties: {
          total_count: 12
        }
      )
    end

    let(:event) do
      build(
        :common_event,
        subscription:,
        organization:,
        billable_metric:,
        properties: {
          billable_metric.field_name => 10
        },
        persisted: false
      )
    end

    let(:filters) { {grouped_by:, matching_filters:, ignored_filters:, event:} }

    it "returns period maximum as aggregation" do
      result = sum_service.aggregate(options:)

      expect(result.options[:running_total]).to eq([12.0, 24.0, 34.0])
    end
  end

  context "when filters are given" do
    let(:matching_filters) { {region: ["europe"]} }

    before do
      create(
        :event,
        organization_id: organization.id,
        code: billable_metric.code,
        customer:,
        subscription:,
        timestamp: to_datetime - 1.day,
        properties: {
          total_count: 12,
          region: "europe"
        }
      )

      create(
        :event,
        organization_id: organization.id,
        code: billable_metric.code,
        customer:,
        subscription:,
        timestamp: to_datetime - 12.hours,
        properties: {
          total_count: 8,
          region: "europe"
        }
      )

      create(
        :event,
        organization_id: organization.id,
        code: billable_metric.code,
        customer:,
        subscription:,
        timestamp: to_datetime - 1.day,
        properties: {
          total_count: 12,
          region: "africa"
        }
      )
    end

    it "aggregates the events" do
      result = sum_service.aggregate(options:)

      expect(result.aggregation).to eq(20)
      expect(result.count).to eq(2)
      expect(result.options).to eq({running_total: [12, 20]})
    end
  end

  context "when filter is given" do
    let(:filter) do
      create(:billable_metric_filter, billable_metric:, key: "region", values: ["north america", "europe", "africa"])
    end
    let(:matching_filters) { {"region" => ["europe"]} }
    let(:ignored_filters) { [] }
    let(:charge_filter) { create(:charge_filter, charge:) }
    let(:filter_value) do
      create(
        :charge_filter_value,
        charge_filter:,
        billable_metric_filter: filter,
        values: ["europe"]
      )
    end

    before do
      filter_value

      create(
        :event,
        organization_id: organization.id,
        code: billable_metric.code,
        customer:,
        subscription:,
        timestamp: to_datetime - 1.day,
        properties: {
          total_count: 12,
          region: "europe"
        }
      )

      create(
        :event,
        organization_id: organization.id,
        code: billable_metric.code,
        customer:,
        subscription:,
        timestamp: to_datetime - 12.hours,
        properties: {
          total_count: 8,
          region: "europe"
        }
      )

      create(
        :event,
        organization_id: organization.id,
        code: billable_metric.code,
        customer:,
        subscription:,
        timestamp: to_datetime - 1.day,
        properties: {
          total_count: 12,
          region: "africa"
        }
      )
    end

    it "aggregates the events" do
      result = sum_service.aggregate(options:)

      expect(result.aggregation).to eq(20)
      expect(result.count).to eq(2)
      expect(result.options).to eq({running_total: [12, 20]})
    end
  end

  context "when subscription was upgraded in the period" do
    let(:old_subscription) do
      create(
        :subscription,
        external_id: subscription.external_id,
        organization:,
        customer:,
        started_at: from_datetime - 10.days,
        terminated_at: from_datetime,
        status: :terminated
      )
    end

    before do
      old_subscription
      subscription.update!(previous_subscription: old_subscription)
      billable_metric.update!(recurring: true)
      create(
        :event,
        organization_id: organization.id,
        code: billable_metric.code,
        customer:,
        subscription: old_subscription,
        timestamp: from_datetime - 5.days,
        properties: {
          total_count: 10
        }
      )
    end

    it "returns the correct number" do
      result = sum_service.aggregate(options:)

      expect(result.aggregation).to eq(63)
    end
  end

  context "when event is given" do
    let(:old_events) { nil }
    let(:latest_events) { nil }
    let(:pay_in_advance_event) do
      create(
        :event,
        organization_id: organization.id,
        code: billable_metric.code,
        customer:,
        subscription:,
        timestamp: to_datetime - 2.days,
        properties:
      )
    end

    let(:properties) { {total_count: 10} }

    it "assigns a pay_in_advance aggregation" do
      result = sum_service.aggregate

      expect(result.pay_in_advance_aggregation).to eq(10)
    end

    context "with presentation group keys" do
      let(:presentation_by) { ["cloud", "region"] }
      let(:properties) { {"total_count" => 10, "cloud" => "aws", "region" => "eu"} }

      it "assigns pay_in_advance_breakdowns based on the pay_in_advance event" do
        result = sum_service.aggregate

        expect(result.pay_in_advance_breakdowns).to eq([
          {groups: {"cloud" => "aws", "region" => "eu"}, value: 10}
        ])
      end
    end

    context "when current period aggregation is greater than period maximum" do
      let(:latest_events) do
        create(
          :event,
          organization_id: organization.id,
          code: billable_metric.code,
          customer:,
          subscription:,
          timestamp: to_datetime - 3.days,
          properties: {
            total_count: -6
          }
        )
      end

      let(:cached_aggregation) do
        create(
          :cached_aggregation,
          organization:,
          charge:,
          external_subscription_id: subscription.external_id,
          timestamp: to_datetime - 3.days,
          current_aggregation: "4",
          max_aggregation: "10"
        )
      end

      before { cached_aggregation }

      it "assigns a pay_in_advance aggregation" do
        result = sum_service.aggregate

        expect(result.pay_in_advance_aggregation).to eq(4)
      end
    end

    context "when current period aggregation is less than period maximum" do
      let(:properties) { {total_count: -2} }
      let(:latest_events) do
        create(
          :event,
          organization_id: organization.id,
          code: billable_metric.code,
          customer:,
          subscription:,
          timestamp: to_datetime - 3.days,
          properties: {
            total_count: -6
          }
        )
      end

      let(:cached_aggregation) do
        create(
          :cached_aggregation,
          organization:,
          charge:,
          event_transaction_id: latest_events.transaction_id,
          external_subscription_id: subscription.external_id,
          timestamp: to_datetime - 3.days,
          current_aggregation: "4",
          max_aggregation: "10"
        )
      end

      before { cached_aggregation }

      it "keeps the subscription event-count contribution without new billed units" do
        result = sum_service.aggregate

        expect(result.pay_in_advance_aggregation).to eq(0)
        expect(result.pay_in_advance_count_delta).to eq(1)
      end

      context "when the event value is zero" do
        let(:properties) { {total_count: 0} }

        it "keeps the event-count contribution" do
          result = sum_service.aggregate

          expect(result.pay_in_advance_aggregation).to be_zero
          expect(result.pay_in_advance_count_delta).to eq(1)
        end
      end
    end

    context "when properties is a float" do
      let(:properties) { {total_count: 12.4} }

      it "assigns a pay_in_advance aggregation" do
        result = sum_service.aggregate

        expect(result.pay_in_advance_aggregation).to eq(12.4)
      end
    end

    context "when event property does not match metric field name" do
      let(:properties) { {final_count: 10} }

      it "assigns 0 as pay_in_advance aggregation" do
        result = sum_service.aggregate

        expect(result.pay_in_advance_aggregation).to be_zero
      end
    end

    context "when event is missing properties" do
      let(:properties) { {} }

      it "assigns 0 as pay_in_advance aggregation" do
        result = sum_service.aggregate

        expect(result.pay_in_advance_aggregation).to be_zero
      end
    end

    context "when a precise_total_amount_cents is present" do
      let(:charge) do
        create(
          :dynamic_charge,
          billable_metric:
        )
      end

      let(:pay_in_advance_event) do
        create(
          :event,
          organization_id: organization.id,
          code: billable_metric.code,
          customer:,
          subscription:,
          timestamp: to_datetime - 2.days,
          properties:,
          precise_total_amount_cents: 1234.02
        )
      end

      it "computes the precise_total_amount_cents" do
        result = sum_service.aggregate

        expect(result.pay_in_advance_aggregation).to eq(10)
        expect(result.precise_total_amount_cents).to eq(1234.02)
        expect(result.pay_in_advance_precise_total_amount_cents).to eq(1234.02)
      end
    end
  end

  context "when rounding is configured" do
    let(:billable_metric) do
      create(
        :billable_metric,
        organization:,
        aggregation_type: "sum_agg",
        field_name: "total_count",
        rounding_function: "ceil",
        rounding_precision: 2
      )
    end

    before do
      latest_events.last.update!(properties: {total_count: 12.434})
    end

    it "aggregates the events" do
      result = sum_service.aggregate(options:)

      expect(result.aggregation).to eq(48.44)
    end
  end

  context "when bypass_aggregation is set to true" do
    let(:bypass_aggregation) { true }

    it "returns a default empty result" do
      result = sum_service.aggregate

      expect(result.aggregation).to eq(0)
      expect(result.count).to eq(0)
      expect(result.current_usage_units).to eq(0)
      expect(result.options).to eq({running_total: []})
    end
  end

  describe ".per_event_aggregation" do
    it "aggregates per events" do
      result = sum_service.per_event_aggregation

      expect(result.event_aggregation).to eq([12, 12, 12, 12])
    end

    context "with grouped_by_values" do
      let(:event) { latest_events.first }

      before do
        event.update!(properties: event.properties.merge(scheme: "visa"))
      end

      it "takes the groups into account" do
        result = sum_service.per_event_aggregation(grouped_by_values: {"scheme" => "visa"})

        expect(result.event_aggregation).to eq([12])
      end
    end

    context "when including event value" do
      let(:event) do
        build(
          :common_event,
          subscription:,
          organization:,
          billable_metric:,
          properties: {
            billable_metric.field_name => 10
          }
        )
      end

      let(:filters) { {grouped_by:, matching_filters:, ignored_filters:, event:} }

      it "includes the event value in the result" do
        result = sum_service.per_event_aggregation(include_event_value: true)

        expect(result.event_aggregation).to eq([12, 12, 12, 12, 10])
      end
    end
  end

  describe ".grouped_by aggregation" do
    let(:grouped_by) { ["agent_name"] }

    let(:agent_names) { %w[aragorn frodo gimli legolas] }

    let(:old_events) { [] }

    let(:latest_events) do
      agent_names.map do |agent_name|
        create(
          :event,
          organization_id: organization.id,
          code: billable_metric.code,
          customer:,
          subscription:,
          timestamp: to_datetime - 1.day,
          properties: {
            total_count: 12,
            agent_name:
          }
        )
      end
    end

    it "returns a grouped aggregations" do
      result = sum_service.aggregate(options:)

      expect(result.aggregations.count).to eq(4)

      result.aggregations.sort_by { |a| a.grouped_by["agent_name"] }.each_with_index do |aggregation, index|
        expect(aggregation.aggregation).to eq(12)
        expect(aggregation.count).to eq(1)
        expect(aggregation.grouped_by["agent_name"]).to eq(agent_names[index])
        expect(aggregation.options[:running_total]).to eq([12])
      end
    end

    context "without events" do
      let(:latest_events) { [] }

      it "returns an empty result" do
        result = sum_service.aggregate(options:)

        expect(result.aggregations.count).to eq(1)

        aggregation = result.aggregations.first
        expect(aggregation.aggregation).to eq(0)
        expect(aggregation.count).to eq(0)
        expect(aggregation.grouped_by).to eq({"agent_name" => nil})
      end
    end

    context "when bypass_aggregation is set to true" do
      let(:bypass_aggregation) { true }

      it "returns an empty result" do
        result = sum_service.aggregate

        expect(result.aggregations.count).to eq(1)

        aggregation = result.aggregations.first
        expect(aggregation.aggregation).to eq(0)
        expect(aggregation.count).to eq(0)
        expect(aggregation.grouped_by).to eq({"agent_name" => nil})
      end
    end

    context "when current usage context and charge is pay in advance" do
      let(:options) do
        {is_pay_in_advance: true, is_current_usage: true}
      end

      let(:cached_aggregation) do
        create(
          :cached_aggregation,
          organization:,
          charge:,
          external_subscription_id: subscription.external_id,
          timestamp: to_datetime - 3.days,
          current_aggregation: "4",
          max_aggregation: "6"
        )
      end

      before do
        billable_metric.update!(recurring: true)
        cached_aggregation
      end

      it "returns period maximum as aggregation" do
        result = sum_service.aggregate(options:)

        expect(result.aggregations.count).to eq(4)

        result.aggregations.sort_by { |a| a.grouped_by["agent_name"] }.each_with_index do |aggregation, index|
          expect(aggregation.aggregation).to eq(12)
          expect(aggregation.count).to eq(1)
          expect(aggregation.grouped_by["agent_name"]).to eq(agent_names[index])
        end
      end

      context "when cached aggregation does not exist" do
        let(:latest_events) { nil }
        let(:cached_aggregation) { nil }

        before { billable_metric.update!(recurring: false) }

        it "returns an empty result" do
          result = sum_service.aggregate(options:)

          expect(result.aggregations.count).to eq(1)

          aggregation = result.aggregations.first
          expect(aggregation.aggregation).to eq(0)
          expect(aggregation.count).to eq(0)
          expect(aggregation.current_usage_units).to eq(0)
          expect(aggregation.grouped_by).to eq({"agent_name" => nil})
        end
      end
    end

    context "when rounding is configured" do
      let(:billable_metric) do
        create(
          :billable_metric,
          organization:,
          aggregation_type: "sum_agg",
          field_name: "total_count",
          rounding_function: "ceil",
          rounding_precision: 2
        )
      end

      let(:last_event) do
        latest_events.last.tap do |e|
          e.update!(properties: {total_count: 12.434, agent_name: e.properties["agent_name"]})
        end
      end

      before { last_event }

      it "aggregates the events" do
        result = sum_service.aggregate(options:)

        expect(result.aggregations.count).to eq(4)

        result.aggregations.sort_by { |a| a.grouped_by["agent_name"] }.each_with_index do |aggregation, index|
          if aggregation.grouped_by["agent_name"] == last_event.properties["agent_name"]
            expect(aggregation.aggregation).to eq(12.44)
          else
            expect(aggregation.aggregation).to eq(12)
          end
          expect(aggregation.count).to eq(1)
          expect(aggregation.grouped_by["agent_name"]).to eq(agent_names[index])
        end
      end
    end

    context "with free units per events" do
      it "returns a result with free units" do
        result = sum_service.aggregate(options: {free_units_per_events: 10})

        expect(result.aggregations.count).to eq(4)

        result.aggregations.each_with_index do |aggregation, index|
          expect(aggregation.options[:running_total]).to eq([12])
        end
      end
    end
  end

  context "with presentation group keys" do
    let(:presentation_by) { ["cloud"] }
    let(:old_events) { [] }

    let(:latest_events) do
      [
        create_list(
          :event,
          3,
          organization_id: organization.id,
          code: billable_metric.code,
          customer:,
          subscription:,
          timestamp: to_datetime - 1.day,
          properties: {total_count: 10, cloud: "aws"}
        ),
        create(
          :event,
          organization_id: organization.id,
          code: billable_metric.code,
          customer:,
          subscription:,
          timestamp: to_datetime - 1.day,
          properties: {total_count: 12, cloud: "gcp"}
        )
      ].flatten
    end

    it "returns the aggregations per group" do
      result = sum_service.aggregate

      expect(result.breakdowns).to match_array([
        {groups: {"cloud" => "aws"}, value: 30},
        {groups: {"cloud" => "gcp"}, value: 12}
      ])
    end

    context "with grouped_by" do
      let(:grouped_by) { ["agent_name"] }

      let(:latest_events) do
        [
          create(
            :event,
            organization_id: organization.id,
            code: billable_metric.code,
            customer:,
            subscription:,
            timestamp: to_datetime - 1.day,
            properties: {total_count: 2, agent_name: "frodo", cloud: "aws"}
          ),
          create(
            :event,
            organization_id: organization.id,
            code: billable_metric.code,
            customer:,
            subscription:,
            timestamp: to_datetime - 1.day,
            properties: {total_count: 7, agent_name: "frodo", cloud: "gcp"}
          ),
          create(
            :event,
            organization_id: organization.id,
            code: billable_metric.code,
            customer:,
            subscription:,
            timestamp: to_datetime - 1.day,
            properties: {total_count: 3, agent_name: "aragorn", cloud: "aws"}
          )
        ]
      end

      it "returns the aggregations per group" do
        result = sum_service.aggregate

        expect(result.breakdowns).to match_array([
          {groups: {"agent_name" => "frodo", "cloud" => "aws"}, value: 2},
          {groups: {"agent_name" => "frodo", "cloud" => "gcp"}, value: 7},
          {groups: {"agent_name" => "aragorn", "cloud" => "aws"}, value: 3}
        ])
      end
    end
  end
end
