# frozen_string_literal: true

require "rails_helper"

RSpec.describe BillableMetrics::ProratedAggregations::SumService, transaction: false do
  subject(:sum_service) do
    described_class.new(
      event_store:,
      metered_item:,
      billing_context:,
      boundaries:,
      filters:
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
        charges_duration: 31,
        timestamp: to_datetime
      )
    )
  end
  let(:boundaries) { {from_datetime:, to_datetime:, charges_duration: 31} }
  let(:billing_context) { Billing::Context.from(subscription:) }
  let(:event_store) do
    event_store_class.new(code: billable_metric.code, billing_context:, boundaries:, filters:)
  end
  let(:filters) { {event: pay_in_advance_event, grouped_by:, presentation_by:, matching_filters:, ignored_filters:} }

  let(:subscription) { create(:subscription, started_at: Time.zone.parse("2022-12-01 00:00:00")) }
  let(:organization) { subscription.organization }
  let(:customer) { subscription.customer }
  let(:grouped_by) { nil }
  let(:presentation_by) { nil }
  let(:matching_filters) { {} }
  let(:ignored_filters) { [] }

  let(:billable_metric) do
    create(
      :billable_metric,
      organization:,
      aggregation_type: "sum_agg",
      field_name: "total_count",
      recurring: true
    )
  end

  let(:charge) do
    create(
      :standard_charge,
      billable_metric:
    )
  end

  let(:from_datetime) { Time.zone.parse("2023-05-01 00:00:00") }
  let(:to_datetime) { Time.zone.parse("2023-05-31 23:59:59") }
  let(:pay_in_advance_event) { nil }
  let(:options) { {} }

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
      2,
      organization_id: organization.id,
      code: billable_metric.code,
      customer:,
      subscription:,
      timestamp: from_datetime + 25.days,
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

    expect(result.aggregation).to eq(9.64517) # 5 + (12*6/31) + (12*6/31)
    expect(result.pay_in_advance_aggregation).to be_zero
    expect(result.count).to eq(4)
  end

  describe "recurring snapshots" do
    let(:old_events) { nil }
    let(:latest_events) { nil }
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

    def aggregate(period, initial_value:, options: {}, charges_duration: nil)
      charges_duration ||= ((period.end - period.begin) / 1.day).ceil
      period_boundaries = {from_datetime: period.begin, to_datetime: period.end, charges_duration:}
      store = event_store_class.new(code: billable_metric.code, billing_context:, boundaries: period_boundaries, filters:)

      described_class.new(event_store: store, metered_item:, billing_context:, boundaries: period_boundaries, filters:, initial_value:)
        .aggregate(options: {recurring_watermark: watermark(period)}.merge(options))
    end

    # The read of the persisted events without the recurring sum of the base aggregator
    def legacy_aggregate(period, **)
      aggregate(period, initial_value: nil, options: {recurring_watermark: nil}, **)
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
      [aggregation_result.grouped_by, aggregation_result.aggregation, aggregation_result.full_units_number, aggregation_result.count]
    end

    before do
      create_event(timestamp: subscription.started_at + 1.day, value: 3, region: "us")
      periods.each_with_index do |period, index|
        create_event(timestamp: period.begin + 10.days, value: 10 * (index + 1), region: "eu")
      end
      create_event(timestamp: periods.last.begin + 20.days, value: 4, region: "apac")

      # Dated in the first period, ingested after its snapshot
      create_event(timestamp: periods.first.begin + 2.days, created_at: watermark(periods.first) + 1.minute, value: 7, region: "eu")
    end

    it "matches the full scan from one period to the next" do
      initial_value = nil

      periods.each do |period|
        from_snapshot = aggregate(period, initial_value:)

        expect(totals(from_snapshot)).to eq(totals(legacy_aggregate(period)))
        initial_value = [snapshot(period, from_snapshot)]
      end

      expect(totals(legacy_aggregate(periods.last))).to eq([nil, BigDecimal("61.74194"), 74, 6]) # 40 + 30 * 21/31 + 4 * 11/31
    end

    it "persists the units ingested up to the watermark" do
      result = aggregate(periods.first, initial_value: nil)

      expect([result.recurring_units, result.recurring_events_count]).to eq([13, 2])
    end

    it "bills the snapshot and the late events over the full period" do
      initial_value = [snapshot(periods.first, aggregate(periods.first, initial_value: nil)).with(units: 1000)]

      result = aggregate(periods.second, initial_value:)

      expect(result.full_units_number).to eq(1000 + 7 + 20)
      expect(result.aggregation).to eq((1007 + 20 * 18.fdiv(28)).ceil(5))
    end

    context "when the subscription terminates in the period" do
      it "prorates the snapshot over the terminated period" do
        initial_value = [snapshot(periods.first, aggregate(periods.first, initial_value: nil))]
        terminated = periods.second.begin..(periods.second.begin + 14.days - 1.second)

        result = aggregate(terminated, initial_value:, charges_duration: 28)

        expect(totals(result)).to eq(totals(legacy_aggregate(terminated, charges_duration: 28)))
      end
    end

    context "with pricing group keys" do
      let(:grouped_by) { %w[region] }

      it "matches the full scan from one period to the next" do
        initial_value = nil

        periods.each do |period|
          from_snapshot = aggregate(period, initial_value:)

          expect(from_snapshot.aggregations.map { totals(it) })
            .to match_array(legacy_aggregate(period).aggregations.map { totals(it) })
          initial_value = from_snapshot.aggregations.map { snapshot(period, it) }
        end
      end
    end

    context "when the charge is paid in advance" do
      let(:initial_value) { [snapshot(periods.first, aggregate(periods.first, initial_value: nil)).with(units: 1000)] }

      it "bills the full amount from the snapshot" do
        result = aggregate(periods.second, initial_value:, options: {is_pay_in_advance: true})

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
        result = aggregate(periods.second, initial_value:, options:)

        expect(result.current_usage_units).to eq(1000 + 7 + 20)
      end
    end
  end

  context "with an event exactly on the period boundary" do
    let(:boundary_event) do
      create(
        :event,
        organization_id: organization.id,
        code: billable_metric.code,
        customer:,
        subscription:,
        timestamp: from_datetime,
        properties: {total_count: 10}
      )
    end

    before { boundary_event }

    it "counts the boundary event once, not in both the persisted and current windows" do
      result = sum_service.aggregate(options:)

      # The event sits on `from_datetime`: it belongs to the current period only.
      # 4 base events + 1 boundary event, counted once (a double-count would report 6).
      expect(result.count).to eq(5)
    end
  end

  context "with presentation group keys" do
    let(:presentation_by) { ["cloud"] }

    let(:latest_events) do
      create_list(
        :event,
        2,
        organization_id: organization.id,
        code: billable_metric.code,
        customer:,
        subscription:,
        timestamp: from_datetime + 25.days,
        properties: {
          total_count: 12,
          cloud: "aws"
        }
      ) + [
        create(
          :event,
          organization_id: organization.id,
          code: billable_metric.code,
          customer:,
          subscription:,
          timestamp: from_datetime + 25.days,
          properties: {
            total_count: 7,
            cloud: "gcp"
          }
        )
      ]
    end

    it "returns the presentation breakdowns" do
      result = sum_service.aggregate(options:)

      aws = result.breakdowns.find { |b| b[:groups]["cloud"] == "aws" }
      gcp = result.breakdowns.find { |b| b[:groups]["cloud"] == "gcp" }

      expect(aws[:value]).to eq(24)
      expect(gcp[:value]).to eq(7)
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
            timestamp: from_datetime + 25.days,
            properties: {
              total_count: 12,
              agent_name: "aragorn",
              cloud: "aws"
            }
          ),
          create(
            :event,
            organization_id: organization.id,
            code: billable_metric.code,
            customer:,
            subscription:,
            timestamp: from_datetime + 25.days,
            properties: {
              total_count: 7,
              agent_name: "aragorn",
              cloud: "gcp"
            }
          ),
          create(
            :event,
            organization_id: organization.id,
            code: billable_metric.code,
            customer:,
            subscription:,
            timestamp: from_datetime + 25.days,
            properties: {
              total_count: 3,
              agent_name: "frodo",
              cloud: "aws"
            }
          )
        ]
      end

      it "returns the presentation breakdowns per group" do
        result = sum_service.aggregate(options:)

        aragorn_aws = result.breakdowns.find { |b| b[:groups] == {"agent_name" => "aragorn", "cloud" => "aws"} }
        aragorn_gcp = result.breakdowns.find { |b| b[:groups] == {"agent_name" => "aragorn", "cloud" => "gcp"} }
        frodo_aws = result.breakdowns.find { |b| b[:groups] == {"agent_name" => "frodo", "cloud" => "aws"} }

        expect(aragorn_aws[:value]).to eq(12)
        expect(aragorn_gcp[:value]).to eq(7)
        expect(frodo_aws[:value]).to eq(3)
      end
    end
  end

  context "when aggregation is performed on billing date for pay in advance case" do
    let(:options) do
      {is_pay_in_advance: true, is_current_usage: false}
    end

    it "aggregates the events without proration" do
      result = sum_service.aggregate(options:)

      expect(result.aggregation).to eq(29)
      expect(result.pay_in_advance_aggregation).to be_zero
      expect(result.count).to eq(4)
    end

    it "does not run the prorated queries" do
      event_store = sum_service.send(:event_store)
      allow(event_store).to receive(:prorated_sum).and_call_original

      sum_service.aggregate(options:)

      expect(event_store).not_to have_received(:prorated_sum)
    end
  end

  context "when events are out of bounds" do
    let(:latest_events) do
      create_list(
        :event,
        4,
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

      expect(result.aggregation).to eq(5)
      expect(result.count).to eq(2)
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
        timestamp: from_datetime + 30.days,
        properties: {
          total_count: 4.5
        }
      )
    end

    it "aggregates the events" do
      result = sum_service.aggregate

      expect(result.aggregation).to eq(9.64517 + 0.14516)
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
        timestamp: from_datetime + 30.days,
        properties: {
          total_count: "foo_bar"
        }
      )
    end

    it "ignores the event" do
      result = sum_service.aggregate

      expect(result).to be_success
      expect(result.aggregation).to eq(9.64517) # 5 + (12*6/31) + (12*6/31)
      expect(result.count).to eq(4)
    end
  end

  context "when current usage context and charge is pay in arrear" do
    let(:options) do
      {is_pay_in_advance: false, is_current_usage: true}
    end

    it "returns period maximum as aggregation" do
      result = sum_service.aggregate(options:)

      expect(result.aggregation).to eq(9.64517)
      expect(result.current_usage_units).to eq(29)
    end

    context "when rounding is configured" do
      let(:billable_metric) do
        create(
          :billable_metric,
          organization:,
          aggregation_type: "sum_agg",
          field_name: "total_count",
          recurring: true,
          rounding_function: "ceil",
          rounding_precision: 2
        )
      end

      before do
        latest_events.last.update!(properties: {total_count: 12.434})
      end

      it "aggregates the events" do
        result = sum_service.aggregate(options:)

        expect(result.aggregation).to eq(9.73)
        expect(result.current_usage_units).to eq(29.44)
      end
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
        organization: billable_metric.organization,
        charge:,
        external_subscription_id: subscription.external_id,
        event_transaction_id: latest_events.transaction_id,
        timestamp: latest_events.timestamp,
        current_aggregation: "4",
        max_aggregation: "6",
        max_aggregation_with_proration: "3.8"
      )
    end

    before { cached_aggregation }

    it "returns period maximum as aggregation" do
      result = sum_service.aggregate(options:)

      expect(result.aggregation).to eq(8.8)
      expect(result.current_usage_units).to eq(9)
    end

    context "when cached aggregation does not exist" do
      let(:latest_events) { nil }
      let(:cached_aggregation) { nil }

      it "returns zero as aggregation" do
        result = sum_service.aggregate(options:)

        expect(result.aggregation).to eq(5)
        expect(result.current_usage_units).to eq(5)
      end
    end

    context "when the aggregated state turned negative after an upfront payment" do
      let(:old_events) { nil }
      let(:latest_events) do
        create(
          :event,
          organization_id: organization.id,
          code: billable_metric.code,
          customer:,
          subscription:,
          timestamp: to_datetime - 3.days,
          properties: {
            total_count: -5
          }
        )
      end

      let(:cached_aggregation) do
        create(
          :cached_aggregation,
          organization: billable_metric.organization,
          charge:,
          external_subscription_id: subscription.external_id,
          event_transaction_id: latest_events.transaction_id,
          timestamp: latest_events.timestamp,
          current_aggregation: "-5",
          max_aggregation: "20",
          max_aggregation_with_proration: "8.5"
        )
      end

      before { cached_aggregation }

      it "does not inflate the aggregation with the negative units" do
        result = sum_service.aggregate(options:)

        expect(result.aggregation).to eq(8.5)
        expect(result.current_usage_units).to eq(0)
      end
    end

    context "when the aggregated state is negative from the start with nothing invoiced" do
      let(:old_events) { nil }
      let(:latest_events) do
        create(
          :event,
          organization_id: organization.id,
          code: billable_metric.code,
          customer:,
          subscription:,
          timestamp: to_datetime - 3.days,
          properties: {
            total_count: -10
          }
        )
      end

      let(:cached_aggregation) do
        create(
          :cached_aggregation,
          organization: billable_metric.organization,
          charge:,
          external_subscription_id: subscription.external_id,
          event_transaction_id: latest_events.transaction_id,
          timestamp: latest_events.timestamp,
          current_aggregation: "-10",
          max_aggregation: "-10",
          max_aggregation_with_proration: "0"
        )
      end

      before { cached_aggregation }

      it "returns zero" do
        result = sum_service.aggregate(options:)

        expect(result.aggregation).to eq(0)
        expect(result.current_usage_units).to eq(0)
      end
    end
  end

  context "when current usage context and charge is pay in advance and just upgraded" do
    let(:from_datetime) { Time.zone.parse("2023-05-15 00:00:00") }
    let(:options) do
      {is_pay_in_advance: true, is_current_usage: true}
    end
    let(:latest_events) { nil }

    it "returns correct values" do
      result = sum_service.aggregate(options:)

      expect(result.aggregation).to eq((5 * 17.fdiv(31)).ceil(5))
      expect(result.current_usage_units).to eq(5)
    end
  end

  context "when current usage context and charge is pay in advance and just upgraded and new event in period" do
    let(:from_datetime) { Time.zone.parse("2023-05-15 00:00:00") }
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
        timestamp: to_datetime - 10.days,
        properties: {
          total_count: 4
        }
      )
    end

    let(:cached_aggregation) do
      create(
        :cached_aggregation,
        organization: billable_metric.organization,
        charge:,
        external_subscription_id: subscription.external_id,
        event_transaction_id: latest_events.transaction_id,
        timestamp: latest_events.timestamp,
        current_aggregation: "4",
        max_aggregation: "6",
        max_aggregation_with_proration: "3.8"
      )
    end

    before { cached_aggregation }

    it "returns correct values" do
      result = sum_service.aggregate(options:)

      expect(result.aggregation).to eq((5 * 17.fdiv(31)).ceil(5) + 3.8)
      expect(result.current_usage_units).to eq(9)
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
        timestamp: from_datetime + 30.days,
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
        timestamp: from_datetime + 30.days,
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
        timestamp: from_datetime + 30.days,
        properties: {
          total_count: 12,
          region: "africa"
        }
      )
    end

    it "aggregates the events" do
      result = sum_service.aggregate(options:)

      expect(result.aggregation).to eq(0.64517) # (1/31 * 8) + (1/31 * 12)
      expect(result.count).to eq(2)
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

      expect(result.aggregation).to eq(19.64517) # 10 + 5 + (6/31*12) + (6/31*12)
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
        timestamp: from_datetime + 29.days,
        properties:
      )
    end

    let(:properties) { {total_count: 10} }

    it "assigns a pay_in_advance aggregation" do
      result = sum_service.aggregate

      expect(result.pay_in_advance_aggregation).to eq(0.64517)
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
          timestamp: from_datetime + 28.days,
          properties: {
            total_count: -6
          }
        )
      end

      let(:cached_aggregation) do
        create(
          :cached_aggregation,
          organization: billable_metric.organization,
          charge:,
          external_subscription_id: subscription.external_id,
          event_transaction_id: latest_events.transaction_id,
          timestamp: latest_events.timestamp,
          current_aggregation: "4",
          max_aggregation: "10",
          max_aggregation_with_proration: "3.2"
        )
      end

      before { cached_aggregation }

      it "assigns a pay_in_advance aggregation" do
        result = sum_service.aggregate

        expect(result.pay_in_advance_aggregation).to eq(0.25807) # 4 * (2/31)
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
          timestamp: from_datetime + 28.days,
          properties: {
            total_count: -6
          }
        )
      end

      let(:cached_aggregation) do
        create(
          :cached_aggregation,
          organization: billable_metric.organization,
          charge:,
          external_subscription_id: subscription.external_id,
          event_transaction_id: latest_events.transaction_id,
          timestamp: latest_events.timestamp,
          current_aggregation: "4",
          max_aggregation: "10",
          max_aggregation_with_proration: "3.2"
        )
      end

      before { cached_aggregation }

      it "assigns a pay_in_advance aggregation" do
        result = sum_service.aggregate

        expect(result.pay_in_advance_aggregation).to eq(0)
        expect(result.units_applied).to eq("-2")
      end
    end

    context "when properties is a float" do
      let(:properties) { {total_count: 12.4} }

      it "assigns a pay_in_advance aggregation" do
        result = sum_service.aggregate

        expect(result.pay_in_advance_aggregation).to eq(0.8) # 2/31*12.4
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
  end

  describe ".per_event_aggregation" do
    it "aggregates per events" do
      sum_service.options = {}
      result = sum_service.per_event_aggregation

      expect(result.event_aggregation).to eq([5, 12, 12])
      expect(result.event_prorated_aggregation.map { |el| el.round(5) }).to eq([5, 2.32258, 2.32258])
    end

    it "reuses the persisted prorated result instead of running a sum query" do
      persisted_store = sum_service.send(:persisted_event_store_instance)
      allow(persisted_store).to receive(:sum).and_call_original

      sum_service.options = {}
      result = sum_service.per_event_aggregation

      expect(result.event_aggregation).to eq([5, 12, 12])
      expect(persisted_store).not_to have_received(:sum)
    end

    context "with grouped_by_values" do
      let(:old_event) { old_events.first }
      let(:latest_event) { latest_events.last }

      before do
        latest_event.update!(properties: latest_event.properties.merge(scheme: "visa"))
        old_event.update!(properties: old_event.properties.merge(scheme: "visa"))
      end

      it "takes the groups into account" do
        sum_service.options = {}
        result = sum_service.per_event_aggregation(grouped_by_values: {"scheme" => "visa"})

        expect(result.event_aggregation).to eq([2.5, 12])
        expect(result.event_prorated_aggregation.map { |el| el.round(5) }).to eq([2.5, 2.32258])
      end
    end

    context "when aggregation is bypassed" do
      subject(:sum_service) do
        described_class.new(
          event_store:,
          metered_item:,
          billing_context:,
          boundaries:,
          filters:,
          bypass_aggregation: true
        )
      end

      let(:billable_metric) do
        create(
          :billable_metric,
          organization:,
          aggregation_type: "sum_agg",
          field_name: "total_count",
          recurring: false
        )
      end

      it "returns empty aggregations without querying the event store" do
        event_store = sum_service.__send__(:event_store)
        allow(event_store).to receive(:prorated_events_values).and_call_original
        allow(event_store).to receive(:events_values).and_call_original

        result = sum_service.per_event_aggregation

        expect(result.event_aggregation).to eq([])
        expect(result.event_prorated_aggregation).to eq([])
        expect(event_store).not_to have_received(:prorated_events_values)
        expect(event_store).not_to have_received(:events_values)
      end
    end

    context "when aggregation is bypassed and metric is recurring" do
      subject(:sum_service) do
        described_class.new(
          event_store:,
          metered_item:,
          billing_context:,
          boundaries:,
          filters:,
          bypass_aggregation: true
        )
      end

      it "ignores the bypass and aggregates per events" do
        sum_service.options = {}
        result = sum_service.per_event_aggregation

        expect(result.event_aggregation).to eq([5, 12, 12])
        expect(result.event_prorated_aggregation.map { |el| el.round(5) }).to eq([5, 2.32258, 2.32258])
      end
    end
  end

  describe ".grouped_by aggregation" do
    let(:grouped_by) { ["agent_name"] }

    let(:agent_names) { %w[aragorn frodo gimli legolas] }

    let(:old_events) do
      agent_names.map do |agent_name|
        create_list(
          :event,
          2,
          organization_id: organization.id,
          code: billable_metric.code,
          customer:,
          subscription:,
          timestamp: subscription.started_at + 3.months,
          properties: {
            total_count: 2.5,
            agent_name:
          }
        )
      end.flatten
    end

    let(:latest_events) do
      agent_names.map do |agent_name|
        create_list(
          :event,
          2,
          organization_id: organization.id,
          code: billable_metric.code,
          customer:,
          subscription:,
          timestamp: from_datetime + 25.days,
          properties: {
            total_count: 12,
            agent_name:
          }
        )
      end.flatten
    end

    it "returns a grouped aggregations" do
      result = sum_service.aggregate(options:)

      expect(result.aggregations.count).to eq(4)

      result.aggregations.sort_by { |a| a.grouped_by["agent_name"] }.each_with_index do |aggregation, index|
        expect(aggregation.aggregation).to eq(9.64517) # 5 + (12*6/31) + (12*6/31)
        expect(aggregation.count).to eq(4)
        expect(aggregation.grouped_by["agent_name"]).to eq(agent_names[index])
      end
    end

    context "when current usage" do
      let(:options) { {is_pay_in_advance:, is_current_usage: true} }
      let(:is_pay_in_advance) { false }
      let(:grouped_by) { ["agent_name"] }
      let(:agent_names) { %w[aragorn] }

      let(:old_events) do
        agent_names.map do |agent_name|
          create_list(
            :event,
            2,
            organization_id: organization.id,
            code: billable_metric.code,
            customer:,
            subscription:,
            timestamp: subscription.started_at + 3.months,
            properties: {
              total_count: 2.5,
              agent_name:
            }
          )
        end.flatten
      end

      let(:latest_events) do
        agent_names.map do |agent_name|
          create_list(
            :event,
            2,
            organization_id: organization.id,
            code: billable_metric.code,
            customer:,
            subscription:,
            timestamp: from_datetime + 25.days,
            properties: {
              total_count: 12,
              agent_name:
            }
          )
        end.flatten
      end

      context "when charge is pay in arrear" do
        it "returns period maximum as aggregation" do
          result = sum_service.aggregate(options:)

          expect(result.aggregations.count).to eq(1)

          result.aggregations.sort_by { |a| a.grouped_by["agent_name"] }.each_with_index do |aggregation, index|
            expect(aggregation.aggregation).to eq(9.64517) # 5 + (12*6/31) + (12*6/31)
            expect(aggregation.count).to eq(4)
            expect(aggregation.current_usage_units).to eq(29)
            expect(aggregation.grouped_by["agent_name"]).to eq(agent_names[index])
          end
        end
      end

      context "when charge is pay in advance" do
        let(:is_pay_in_advance) { true }

        let(:latest_events) do
          agent_names.map do |agent_name|
            create(
              :event,
              organization_id: organization.id,
              code: billable_metric.code,
              customer:,
              subscription:,
              timestamp: to_datetime - 3.days,
              properties: {
                total_count: 4,
                agent_name:
              }
            )
          end.flatten
        end

        let(:cached_aggregation) do
          create(
            :cached_aggregation,
            organization: billable_metric.organization,
            charge:,
            external_subscription_id: subscription.external_id,
            event_transaction_id: latest_events.first.transaction_id,
            timestamp: latest_events.first.timestamp,
            current_aggregation: "4",
            max_aggregation: "6",
            max_aggregation_with_proration: "3.8",
            grouped_by: {"agent_name" => agent_names.first}
          )
        end

        before { cached_aggregation }

        it "returns period maximum as aggregation" do
          result = sum_service.aggregate(options:)

          expect(result.aggregations.count).to eq(1)

          result.aggregations.sort_by { |a| a.grouped_by["agent_name"] }.each_with_index do |aggregation, index|
            expect(aggregation.aggregation).to eq(8.8)
            expect(aggregation.current_usage_units).to eq(9)
            expect(aggregation.grouped_by["agent_name"]).to eq(agent_names[index])
          end
        end

        context "when cached aggregation does not exist" do
          let(:latest_events) { nil }
          let(:cached_aggregation) { nil }

          it "returns zero as aggregation" do
            result = sum_service.aggregate(options:)

            expect(result.aggregations.count).to eq(1)

            result.aggregations.sort_by { |a| a.grouped_by["agent_name"] }.each_with_index do |aggregation, index|
              expect(aggregation.aggregation).to eq(5)
              expect(aggregation.current_usage_units).to eq(5)
              expect(aggregation.grouped_by["agent_name"]).to eq(agent_names[index])
            end
          end
        end
      end

      context "when charge is pay in advance and just upgraded" do
        let(:from_datetime) { Time.zone.parse("2023-05-15 00:00:00") }
        let(:is_pay_in_advance) { true }
        let(:latest_events) { nil }

        it "returns correct values" do
          result = sum_service.aggregate(options:)

          expect(result.aggregations.count).to eq(1)

          result.aggregations.sort_by { |a| a.grouped_by["agent_name"] }.each_with_index do |aggregation, index|
            expect(aggregation.aggregation).to eq((5 * 17.fdiv(31)).ceil(5))
            expect(aggregation.current_usage_units).to eq(5)
            expect(aggregation.grouped_by["agent_name"]).to eq(agent_names[index])
          end
        end
      end

      context "when charge is pay in advance and just upgraded and new event in period" do
        let(:from_datetime) { Time.zone.parse("2023-05-15 00:00:00") }
        let(:is_pay_in_advance) { true }

        let(:latest_events) do
          agent_names.map do |agent_name|
            create(
              :event,
              organization_id: organization.id,
              code: billable_metric.code,
              customer:,
              subscription:,
              timestamp: to_datetime - 10.days,
              properties: {
                total_count: 4,
                agent_name:
              }
            )
          end.flatten
        end

        let(:cached_aggregation) do
          create(
            :cached_aggregation,
            organization: billable_metric.organization,
            charge:,
            external_subscription_id: subscription.external_id,
            event_transaction_id: latest_events.first.transaction_id,
            timestamp: latest_events.first.timestamp,
            current_aggregation: "4",
            max_aggregation: "6",
            max_aggregation_with_proration: "3.8",
            grouped_by: {"agent_name" => agent_names.first}
          )
        end

        before { cached_aggregation }

        it "returns correct values" do
          result = sum_service.aggregate(options:)

          expect(result.aggregations.count).to eq(1)

          result.aggregations.sort_by { |a| a.grouped_by["agent_name"] }.each_with_index do |aggregation, index|
            expect(aggregation.aggregation).to eq((5 * 17.fdiv(31)).ceil(5) + 3.8)
            expect(aggregation.current_usage_units).to eq(9)
            expect(aggregation.grouped_by["agent_name"]).to eq(agent_names[index])
          end
        end
      end
    end
  end
end
