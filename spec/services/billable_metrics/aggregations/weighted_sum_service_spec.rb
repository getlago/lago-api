# frozen_string_literal: true

require "rails_helper"

RSpec.describe BillableMetrics::Aggregations::WeightedSumService, transaction: false do
  subject(:aggregator) do
    described_class.new(
      event_store:,
      metered_item:,
      billing_context:,
      boundaries:,
      filters:,
      bypass_aggregation:,
      initial_value:,
      initial_period:
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
        charges_duration:,
        timestamp: to_datetime
      )
    )
  end
  let(:boundaries) { {from_datetime:, to_datetime:, charges_duration:} }
  let(:billing_context) { Billing::Context.from(subscription:) }
  let(:event_store) do
    event_store_class.new(code: billable_metric.code, billing_context:, boundaries:, filters:)
  end
  let(:bypass_aggregation) { false }
  let(:filters) { {grouped_by:, presentation_by:, matching_filters:, ignored_filters:} }

  let(:subscription) { create(:subscription, started_at: DateTime.parse("2023-04-01 22:22:22")) }
  let(:organization) { subscription.organization }
  let(:customer) { subscription.customer }
  let(:grouped_by) { nil }
  let(:matching_filters) { nil }
  let(:ignored_filters) { nil }
  let(:presentation_by) { nil }

  let(:billable_metric) { create(:weighted_sum_billable_metric, organization:) }

  let(:charge) do
    create(
      :standard_charge,
      billable_metric:
    )
  end

  let(:from_datetime) { Time.zone.parse("2023-08-01 00:00:00.000") }
  let(:to_datetime) { Time.zone.parse("2023-08-31 23:59:59.999") }
  let(:charges_duration) { 31 }
  let(:initial_value) { nil }
  let(:initial_period) { closed_period(initial_value.first&.to_datetime || from_datetime - 1.second) unless initial_value.nil? }

  let(:events_values) do
    [
      {timestamp: Time.zone.parse("2023-08-01 00:00:00.000"), value: 2},
      {timestamp: Time.zone.parse("2023-08-01 01:00:00"), value: 3},
      {timestamp: Time.zone.parse("2023-08-01 01:30:00"), value: 1},
      {timestamp: Time.zone.parse("2023-08-01 02:00:00"), value: -4},
      {timestamp: Time.zone.parse("2023-08-01 04:00:00"), value: -2},
      {timestamp: Time.zone.parse("2023-08-01 05:00:00"), value: 10},
      {timestamp: Time.zone.parse("2023-08-01 05:30:00"), value: -10}
    ]
  end

  def closed_period(to_datetime)
    RecurringAggregationSnapshots::FetchService::Period.new(to_datetime:, watermark: to_datetime)
  end

  def snapshot(units:, grouped_by: {}, presentation_breakdowns: [], to_datetime: from_datetime - 1.second)
    RecurringAggregationSnapshots::FetchService::Snapshot.new(
      grouped_by:, units:, events_count: 0, presentation_breakdowns:, to_datetime:, watermark: to_datetime
    )
  end

  before do
    events_values.each do |values|
      properties = {value: values[:value]}
      properties[:region] = values[:region] if values[:region]
      properties[:agent_name] = values[:agent_name] if values[:agent_name]

      create(
        :event,
        organization_id: organization.id,
        code: billable_metric.code,
        subscription:,
        customer:,
        timestamp: values[:timestamp],
        properties:
      )
    end
  end

  it "aggregates the events" do
    result = aggregator.aggregate

    expect(result.aggregation.round(5).to_s).to eq("0.02218")
    expect(result.count).to eq(7)
  end

  context "when using presentation_by" do
    let(:presentation_by) { ["region"] }

    let(:events_values) do
      [
        {timestamp: Time.zone.parse("2023-08-01 00:00:00.000"), value: 2, region: "eu"},
        {timestamp: Time.zone.parse("2023-08-01 01:00:00"), value: 3, region: "us"},
        {timestamp: Time.zone.parse("2023-08-01 02:00:00"), value: -1, region: "eu"}
      ]
    end

    it "returns aggregations per group" do
      result = aggregator.aggregate

      region_eu = result.breakdowns.find { |b| b[:groups]["region"] == "eu" }
      expect(region_eu[:value].round(5).to_s).to eq("1.00269")

      region_us = result.breakdowns.find { |b| b[:groups]["region"] == "us" }
      expect(region_us[:value].round(5).to_s).to eq("2.99597")
    end
  end

  context "with a single event" do
    let(:events_values) do
      [
        {timestamp: Time.zone.parse("2023-08-01 00:00:00.000"), value: 1000}
      ]
    end

    it "aggregates the events" do
      result = aggregator.aggregate

      expect(result.aggregation.round(5).to_s).to eq("1000.0")
      expect(result.count).to eq(1)
    end
  end

  context "with no events" do
    let(:events_values) { [] }

    it "aggregates the events" do
      result = aggregator.aggregate

      expect(result.aggregation.round(5).to_s).to eq("0.0")
      expect(result.count).to eq(0)
      expect(result.options).to eq({})
    end
  end

  context "when bypass_aggregation is set to true" do
    let(:bypass_aggregation) { true }

    it "returns a default empty result" do
      result = aggregator.aggregate

      expect(result.aggregation).to eq(0)
      expect(result.count).to eq(0)
      expect(result.current_usage_units).to eq(0)
      expect(result.options).to eq({running_total: []})
    end
  end

  context "with cycle carryover variation" do
    let(:events_values) { [] }
    let(:opening_variations) { {nil => BigDecimal("31.5")} }
    let(:cycle_usage_tracker) do
      instance_double(Fees::ChargeService::Trackers::CycleCarryoverVariation,
        carryover_variation?: true, opening_variations:, apply_closing_values?: false, apply_carry_over?: false)
    end

    before do
      allow(cycle_usage_tracker).to receive(:each_opening_balance) do |groups:, **, &block|
        groups.each { |group| block.call(group, BigDecimal("31.5")) }
      end
    end

    shared_examples "weights the opening variation" do
      it "retains the raw opening quantity without adding events or tier carryover" do
        result = aggregator.aggregate(cycle_usage_tracker:)

        expect(result).to have_attributes(aggregation: BigDecimal("31.5"), variation: 0, count: 0,
          carryover_variation: BigDecimal("31.5"), carryover_units: nil)
      end
    end

    include_examples "weights the opening variation"

    context "when the period filter reports no local events" do
      let(:bypass_aggregation) { true }

      include_examples "weights the opening variation"
    end

    shared_examples "weights an eventless pricing group" do
      let(:grouped_by) { ["region"] }
      let(:opening_variations) { {{"region" => "EU"} => BigDecimal("31.5")} }

      it "uses the carried group without reading recurring history" do
        result = aggregator.aggregate(cycle_usage_tracker:)

        expect(result.aggregations.sole).to have_attributes(grouped_by: {"region" => "EU"},
          aggregation: BigDecimal("31.5"), variation: 0, count: 0,
          carryover_variation: BigDecimal("31.5"), carryover_units: nil)
      end
    end

    context "with an eventless pricing group" do
      include_examples "weights an eventless pricing group"
    end

    context "with ClickHouse events", clickhouse: true do
      let(:event_store_class) { Events::Stores::ClickhouseStore }

      include_examples "weights the opening variation"

      context "with an eventless pricing group" do
        include_examples "weights an eventless pricing group"
      end
    end
  end

  context "with events with the same timestamp" do
    let(:events_values) do
      [
        {timestamp: Time.zone.parse("2023-08-01 00:00:00.000"), value: 3},
        {timestamp: Time.zone.parse("2023-08-01 00:00:00.000"), value: 3}
      ]
    end

    it "aggregates the events" do
      result = aggregator.aggregate

      expect(result.aggregation).to eq(6)
      expect(result.count).to eq(2)
    end
  end

  context "when billable metric is recurring" do
    let(:billable_metric) { create(:weighted_sum_billable_metric, :recurring, organization:) }

    let(:events_values) { [] }

    let(:cached_aggregation) do
      create(
        :cached_aggregation,
        charge:,
        organization:,
        external_subscription_id: subscription.external_id,
        timestamp: from_datetime - 1.day,
        current_aggregation: 1000
      )
    end

    before { cached_aggregation }

    it "uses the persisted recurring value as initial value" do
      result = aggregator.aggregate

      expect(result.aggregation.to_s).to eq("1000.0")
      expect(result.count).to eq(0)
      expect(result.variation).to eq(0)
      expect(result.total_aggregated_units).to eq(1000)
      expect(result.recurring_updated_at).to eq(from_datetime)
    end

    context "with a snapshot of the previous period" do
      let(:initial_value) { [snapshot(units: 400)] }

      it "uses the snapshot as initial value" do
        result = aggregator.aggregate

        expect(result.aggregation).to eq(400)
        expect(result.total_aggregated_units).to eq(400)
        expect(result.recurring_units).to eq(400)
      end

      context "when using presentation_by" do
        let(:presentation_by) { ["region"] }
        let(:initial_value) do
          [snapshot(units: 400, presentation_breakdowns: [{groups: {"region" => "eu"}, value: "400.0"}])]
        end

        it "uses the snapshot presentation breakdowns as initial values" do
          expect(aggregator.aggregate.breakdowns).to eq([{groups: {"region" => "eu"}, value: 400.to_d}])
        end
      end

      context "when the snapshot closes an older period" do
        let(:snapshot_to_datetime) { from_datetime - 1.month - 1.second }
        let(:initial_value) do
          [snapshot(units: 400, to_datetime: snapshot_to_datetime, presentation_breakdowns: [{"groups" => {"region" => "eu"}, "value" => "400.0"}])]
        end
        let(:events_values) do
          [
            {timestamp: snapshot_to_datetime, value: 7, region: "eu"},
            {timestamp: from_datetime - 10.days, value: 5, region: "eu"},
            {timestamp: from_datetime - 5.days, value: 2, region: "us"}
          ]
        end

        it "adds the events dated after the snapshot period, as the invoice of the unbilled period will" do
          # 400 + 5 + 2, the event dated at the snapshot period end is in the snapshot
          expect(aggregator.aggregate.total_aggregated_units).to eq(407)
        end

        context "with ClickHouse events", clickhouse: true do
          let(:event_store_class) { Events::Stores::ClickhouseStore }
          let(:organization) { create(:organization, clickhouse_events_store: true) }
          let(:subscription) { create(:subscription, organization:, started_at: DateTime.parse("2023-04-01 22:22:22")) }
          let(:events_values) { [] }

          before do
            {snapshot_to_datetime => 7, from_datetime - 0.001.seconds => 5, from_datetime => 2}.each do |timestamp, value|
              create(:clickhouse_events_enriched, organization:, subscription:, customer:, billable_metric:,
                timestamp:, value: value.to_s, decimal_value: value)
            end
          end

          it "reads each event once across the snapshot, the unbilled period and this one" do
            # 400 + 5 dated a millisecond before this period + 2 dated at its start; the 7 is in the snapshot
            expect(aggregator.aggregate.total_aggregated_units).to eq(407)
          end
        end

        context "when an invoice closed a later period" do
          before do
            create(:invoice_subscription, subscription:, invoicing_reason: :subscription_periodic,
              charges_from_datetime: from_datetime - 1.month, charges_to_datetime: from_datetime - 1.second)
          end

          it "uses the persisted recurring value of that invoice" do
            expect(aggregator.aggregate.total_aggregated_units).to eq(1000)
          end
        end

        # An upgrade whose terminating invoice skipped the charge kept by the new plan: the new
        # subscription has no invoice of its own, so no invoice tells the snapshot is outdated
        context "when the snapshot is the previous subscription's" do
          let(:initial_period) do
            RecurringAggregationSnapshots::FetchService::Period.new(
              to_datetime: snapshot_to_datetime, watermark: snapshot_to_datetime, inherited: true
            )
          end

          it "uses the persisted recurring value, as without snapshots" do
            expect(aggregator.aggregate.total_aggregated_units).to eq(1000)
          end
        end

        context "when using presentation_by" do
          let(:presentation_by) { ["region"] }

          it "adds them to the snapshot presentation breakdowns" do
            expect(aggregator.aggregate.breakdowns).to match_array(
              [{groups: {"region" => "eu"}, value: 405.to_d}, {groups: {"region" => "us"}, value: 2.to_d}]
            )
          end
        end
      end

      context "when the snapshot closes after the period starts" do
        let(:initial_value) { [snapshot(units: 400, to_datetime: from_datetime + 1.second)] }

        it "uses the persisted recurring value as initial value" do
          expect(aggregator.aggregate.total_aggregated_units).to eq(1000)
        end
      end

      context "when the bucket had no active units at the end of the previous period" do
        let(:initial_value) { [] }
        let(:presentation_by) { ["region"] }

        it "starts from zero units and breakdowns" do
          result = aggregator.aggregate

          expect([result.aggregation, result.total_aggregated_units, result.recurring_units, result.breakdowns]).to eq([0, 0, 0, []])
        end

        context "when the period is older" do
          let(:initial_period) { closed_period(from_datetime - 1.month - 1.second) }
          let(:events_values) { [{timestamp: from_datetime - 10.days, value: 5, region: "eu"}] }

          it "starts from the events dated after it" do
            result = aggregator.aggregate

            expect([result.total_aggregated_units, result.breakdowns]).to eq([5, [{groups: {"region" => "eu"}, value: 5.to_d}]])
          end
        end
      end
    end

    context "when the previous period is closed but not invoiced yet" do
      let(:billed_to_datetime) { from_datetime - 1.month - 1.second }
      let(:cached_aggregation) do
        create(:cached_aggregation, charge:, organization:, external_subscription_id: subscription.external_id,
          timestamp: billed_to_datetime - 5.days, current_aggregation: 1000, created_at: cached_at)
      end
      # Written by the invoice of the period it closes, after that period ends
      let(:cached_at) { billed_to_datetime + 10.minutes }
      let(:events_values) do
        [
          # Dated in the invoiced period, after its last event: ignored as a late event
          {timestamp: billed_to_datetime - 1.day, value: 7},
          {timestamp: from_datetime - 10.days, value: 5}
        ]
      end

      before do
        create(:invoice_subscription, subscription:, invoicing_reason: :subscription_periodic,
          charges_from_datetime: billed_to_datetime.beginning_of_month, charges_to_datetime: billed_to_datetime)
      end

      it "adds the events of the unbilled period to the persisted recurring value" do
        expect(aggregator.aggregate.total_aggregated_units).to eq(1005)
      end

      context "when only a progressive billing invoice covers the previous period" do
        before do
          create(:invoice_subscription, subscription:, invoicing_reason: :progressive_billing,
            charges_from_datetime: from_datetime - 1.month, charges_to_datetime: from_datetime - 1.second)
          # Written by the progressive billing invoice: 1000 + 5, at its last event
          create(:cached_aggregation, charge:, organization:, external_subscription_id: subscription.external_id,
            timestamp: from_datetime - 10.days, current_aggregation: 1005, created_at: from_datetime - 5.days)
        end

        it "starts from the invoiced period and adds its events once" do
          # 1000 at the last invoiced period + 5 dated in the unbilled one
          expect(aggregator.aggregate.total_aggregated_units).to eq(1005)
        end

        context "when the last invoiced period wrote no cached aggregation" do
          let(:cached_aggregation) {}

          it "starts from zero and adds the events of the unbilled period" do
            # No level before the progressive billing invoice + 5 dated in the unbilled period
            expect(aggregator.aggregate.total_aggregated_units).to eq(5)
          end

          context "when the subscription comes from a plan change" do
            let(:previous_subscription) do
              create(:subscription, :terminated, started_at: DateTime.parse("2022-01-01 22:22:22"),
                terminated_at: DateTime.parse("2023-04-01 22:22:21"))
            end
            let(:customer) { previous_subscription.customer }
            let(:subscription) do
              create(:subscription, started_at: DateTime.parse("2023-04-01 22:22:22"), previous_subscription:,
                customer:, external_id: previous_subscription.external_id)
            end

            before do
              create(:event, organization_id: organization.id, code: billable_metric.code, subscription: previous_subscription,
                customer:, timestamp: Time.zone.parse("2023-03-01 22:22:22"), properties: {value: 10})
            end

            it "reads the history of the external id, as the coming invoice will" do
              # 10 from the previous subscription + 7 and 5 of this one, unbilled period included
              expect(aggregator.aggregate.total_aggregated_units).to eq(22)
            end
          end
        end
      end

      context "when the previous period is invoiced" do
        before do
          create(:invoice_subscription, subscription:, invoicing_reason: :subscription_periodic,
            charges_from_datetime: from_datetime - 1.month, charges_to_datetime: from_datetime - 1.second)
        end

        it "uses the persisted recurring value as initial value" do
          expect(aggregator.aggregate.total_aggregated_units).to eq(1000)
        end
      end

      context "when the cached aggregation was written after the period started" do
        let(:cached_at) { from_datetime + 10.minutes }

        it "takes it for the invoice of the previous period and adds no event" do
          expect(aggregator.aggregate.total_aggregated_units).to eq(1000)
        end
      end
    end

    context "when using presentation_by with no current events and zero initial value" do
      let(:presentation_by) { ["region"] }
      let(:events_values) { [] }
      let(:cached_aggregation) do
        create(
          :cached_aggregation,
          charge:,
          organization:,
          external_subscription_id: subscription.external_id,
          timestamp: from_datetime - 1.day,
          current_aggregation: 0,
          presentation_breakdowns: [{"groups" => {"region" => "eu"}, "value" => "100.0"}]
        )
      end

      it "falls back to cached presentation breakdowns" do
        result = aggregator.aggregate

        expect(result.breakdowns).to eq([{groups: {"region" => "eu"}, value: 100.to_d}])
        expect(result.recurring_breakdowns).to eq([{groups: {"region" => "eu"}, value: 100.to_d}])
      end
    end

    context "when using presentation_by with events and cached presentation breakdowns" do
      let(:presentation_by) { ["region"] }
      let(:events_values) do
        [
          {timestamp: Time.zone.parse("2023-08-16 00:00:00"), value: 10, region: "eu"},
          {timestamp: Time.zone.parse("2023-08-16 00:00:00"), value: 4, region: "us"}
        ]
      end
      let(:cached_aggregation) do
        create(
          :cached_aggregation,
          charge:,
          organization:,
          external_subscription_id: subscription.external_id,
          timestamp: from_datetime - 1.day,
          current_aggregation: 100,
          presentation_breakdowns: [{"groups" => {"region" => "eu"}, "value" => "100.0"}]
        )
      end

      it "returns the weighted breakdowns and the units active at period end" do
        result = aggregator.aggregate

        expect(result.breakdowns.map { {groups: it[:groups], value: it[:value].round(5).to_s} }).to match_array(
          [
            {groups: {"region" => "eu"}, value: "105.16129"},
            {groups: {"region" => "us"}, value: "2.06452"}
          ]
        )
        expect(result.recurring_breakdowns).to match_array(
          [
            {groups: {"region" => "eu"}, value: 110},
            {groups: {"region" => "us"}, value: 4}
          ]
        )
      end
    end

    context "without cached_aggregation" do
      let(:cached_aggregation) {}

      it "falls back on 0" do
        result = aggregator.aggregate

        expect(result.aggregation.round(5).to_s).to eq("0.0")
        expect(result.count).to eq(0)
        expect(result.variation).to eq(0)
        expect(result.total_aggregated_units).to eq(0)
        expect(result.recurring_updated_at).to eq(from_datetime)
      end

      context "with events attached to a previous subcription" do
        let(:previous_subscription) do
          create(
            :subscription,
            :terminated,
            started_at: DateTime.parse("2022-01-01 22:22:22"),
            terminated_at: DateTime.parse("2023-04-01 22:22:21")
          )
        end

        let(:customer) { previous_subscription.customer }

        let(:subscription) do
          create(
            :subscription,
            started_at: DateTime.parse("2023-04-01 22:22:22"),
            previous_subscription:,
            customer:,
            external_id: previous_subscription.external_id
          )
        end

        before do
          subscription

          create(
            :event,
            organization_id: organization.id,
            code: billable_metric.code,
            subscription: previous_subscription,
            customer:,
            timestamp: Time.zone.parse("2023-03-01 22:22:22"),
            properties: {value: 10}
          )
        end

        it "uses previous events as latest value" do
          result = aggregator.aggregate

          expect(result.aggregation.round(5).to_s).to eq("10.0")
          expect(result.count).to eq(0)
          expect(result.variation).to eq(0)
          expect(result.total_aggregated_units).to eq(10)
          expect(result.recurring_updated_at).to eq(from_datetime)
        end

        context "when an event falls just before the subscription boundary" do
          before do
            create(
              :event,
              organization_id: organization.id,
              code: billable_metric.code,
              subscription: previous_subscription,
              customer:,
              timestamp: from_datetime - 0.5.seconds,
              properties: {value: 5}
            )
          end

          it "includes the event in the recurring value" do
            result = aggregator.aggregate

            expect(result.total_aggregated_units).to eq(15)
          end
        end

        context "with ClickHouse events", clickhouse: true do
          let(:event_store_class) { Events::Stores::ClickhouseStore }
          let(:organization) { create(:organization, clickhouse_events_store: true) }
          let(:previous_subscription) do
            create(
              :subscription,
              :terminated,
              organization:,
              started_at: DateTime.parse("2022-01-01 22:22:22"),
              terminated_at: DateTime.parse("2023-04-01 22:22:21")
            )
          end
          let(:customer) { previous_subscription.customer }
          let(:subscription) do
            create(
              :subscription,
              organization:,
              started_at: DateTime.parse("2023-04-01 22:22:22"),
              previous_subscription:,
              customer:,
              external_id: previous_subscription.external_id
            )
          end

          before do
            create(
              :clickhouse_events_enriched,
              organization:,
              subscription:,
              customer:,
              billable_metric:,
              timestamp: from_datetime - 0.001.seconds,
              value: "5",
              decimal_value: 5
            )
            create(
              :clickhouse_events_enriched,
              organization:,
              subscription:,
              customer:,
              billable_metric:,
              timestamp: from_datetime - 0.5.seconds,
              value: "2",
              decimal_value: 2
            )
            create(
              :clickhouse_events_enriched,
              organization:,
              subscription:,
              customer:,
              billable_metric:,
              timestamp: from_datetime,
              value: "100",
              decimal_value: 100
            )
          end

          it "keeps the exact-boundary event in the current interval" do
            result = aggregator.aggregate

            expect(result.variation).to eq(100)
            expect(result.total_aggregated_units).to eq(107)
          end
        end

        context "when using presentation_by" do
          let(:presentation_by) { ["region"] }

          let(:events_values) do
            [
              {timestamp: Time.zone.parse("2023-08-01 00:00:00.000"), value: 2, region: "eu"},
              {timestamp: Time.zone.parse("2023-08-01 01:00:00"), value: 3, region: "eu"}
            ]
          end

          it "returns aggregations per group" do
            result = aggregator.aggregate

            region_eu = result.breakdowns.find { |b| b[:groups]["region"] == "eu" }
            expect(region_eu[:value].round(5).to_s).to eq("4.99597")

            region_nil = result.breakdowns.find { |b| b[:groups]["region"].nil? }
            expect(region_nil[:value].round(5).to_s).to eq("10.0")
          end
        end
      end
    end

    context "with events" do
      let(:events_values) do
        [
          {timestamp: DateTime.parse("2023-08-01 00:00:00.000"), value: 2},
          {timestamp: DateTime.parse("2023-08-01 01:00:00"), value: 3},
          {timestamp: DateTime.parse("2023-08-01 01:30:00"), value: 1},
          {timestamp: DateTime.parse("2023-08-01 02:00:00"), value: -4},
          {timestamp: DateTime.parse("2023-08-01 04:00:00"), value: -2},
          {timestamp: DateTime.parse("2023-08-01 05:00:00"), value: 10},
          {timestamp: DateTime.parse("2023-08-01 05:30:00"), value: -10}
        ]
      end

      it "aggregates the events" do
        result = aggregator.aggregate

        expect(result.aggregation.round(5).to_s).to eq("1000.02218")
        expect(result.count).to eq(7)
        expect(result.variation).to eq(0)
        expect(result.total_aggregated_units).to eq(1000)
        expect(result.recurring_updated_at).to eq("2023-08-01 05:30:00")
      end
    end
  end

  context "with filters" do
    let(:matching_filters) { {region: ["europe"]} }

    let(:events_values) do
      [
        {timestamp: DateTime.parse("2023-08-01 00:00:00.000"), value: 1000, region: "europe"}
      ]
    end

    it "aggregates the events" do
      result = aggregator.aggregate

      expect(result.aggregation.to_s).to eq("1000.0")
      expect(result.count).to eq(1)
    end
  end

  describe ".grouped_by aggregation" do
    let(:grouped_by) { ["agent_name"] }
    let(:agent_names) { %w[aragorn frodo] }

    let(:events_values) do
      [
        {timestamp: Time.zone.parse("2023-08-01 00:00:00.000"), value: 2, agent_name: "aragorn"},
        {timestamp: Time.zone.parse("2023-08-01 01:00:00"), value: 3, agent_name: "aragorn"},
        {timestamp: Time.zone.parse("2023-08-01 01:30:00"), value: 1, agent_name: "aragorn"},
        {timestamp: Time.zone.parse("2023-08-01 02:00:00"), value: -4, agent_name: "aragorn"},
        {timestamp: Time.zone.parse("2023-08-01 04:00:00"), value: -2, agent_name: "aragorn"},
        {timestamp: Time.zone.parse("2023-08-01 05:00:00"), value: 10, agent_name: "aragorn"},
        {timestamp: Time.zone.parse("2023-08-01 05:30:00"), value: -10, agent_name: "aragorn"},

        {timestamp: Time.zone.parse("2023-08-01 00:00:00.000"), value: 2, agent_name: "frodo"},
        {timestamp: Time.zone.parse("2023-08-01 01:00:00"), value: 3, agent_name: "frodo"},
        {timestamp: Time.zone.parse("2023-08-01 01:30:00"), value: 1, agent_name: "frodo"},
        {timestamp: Time.zone.parse("2023-08-01 02:00:00"), value: -4, agent_name: "frodo"},
        {timestamp: Time.zone.parse("2023-08-01 04:00:00"), value: -2, agent_name: "frodo"},
        {timestamp: Time.zone.parse("2023-08-01 05:00:00"), value: 10, agent_name: "frodo"},
        {timestamp: Time.zone.parse("2023-08-01 05:30:00"), value: -10, agent_name: "frodo"}
      ]
    end

    it "returns a grouped aggregations" do
      result = aggregator.aggregate

      expect(result.aggregations.count).to eq(2)

      result.aggregations.sort_by { |a| a.grouped_by["agent_name"] }.each_with_index do |aggregation, index|
        expect(aggregation.aggregation.round(5).to_s).to eq("0.02218")
        expect(aggregation.count).to eq(7)
        expect(aggregation.grouped_by["agent_name"]).to eq(agent_names[index])
      end
    end

    context "with no events" do
      let(:events_values) { [] }

      it "returns an empty result" do
        result = aggregator.aggregate

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
        result = aggregator.aggregate

        expect(result.aggregations.count).to eq(1)

        aggregation = result.aggregations.first
        expect(aggregation.aggregation).to eq(0)
        expect(aggregation.count).to eq(0)
        expect(aggregation.grouped_by).to eq({"agent_name" => nil})
      end
    end

    context "with events with the same timestamp" do
      let(:events_values) do
        [
          {timestamp: Time.zone.parse("2023-08-01 00:00:00.000"), value: 3, agent_name: "aragorn"},
          {timestamp: Time.zone.parse("2023-08-01 00:00:00.000"), value: 3, agent_name: "aragorn"},

          {timestamp: Time.zone.parse("2023-08-01 00:00:00.000"), value: 3, agent_name: "frodo"},
          {timestamp: Time.zone.parse("2023-08-01 00:00:00.000"), value: 3, agent_name: "frodo"}
        ]
      end

      it "aggregates the events" do
        result = aggregator.aggregate

        expect(result.aggregations.count).to eq(2)

        result.aggregations.sort_by { |a| a.grouped_by["agent_name"] }.each_with_index do |aggregation, index|
          expect(aggregation.aggregation.round(5)).to eq(6)
          expect(aggregation.count).to eq(2)
          expect(aggregation.grouped_by["agent_name"]).to eq(agent_names[index])
        end
      end
    end

    context "when billable metric is recurring" do
      let(:billable_metric) { create(:weighted_sum_billable_metric, :recurring, organization:) }

      let(:events_values) { [] }
      let(:aragorn_presentation_breakdowns) { [] }
      let(:frodo_presentation_breakdowns) { [] }

      let(:cached_aggregations) do
        [
          create(
            :cached_aggregation,
            organization:,
            charge:,
            external_subscription_id: subscription.external_id,
            timestamp: from_datetime - 1.day,
            current_aggregation: 1000,
            grouped_by: {"agent_name" => "aragorn"},
            presentation_breakdowns: aragorn_presentation_breakdowns
          ),

          create(
            :cached_aggregation,
            organization:,
            charge:,
            external_subscription_id: subscription.external_id,
            timestamp: from_datetime - 1.day,
            current_aggregation: 1000,
            grouped_by: {"agent_name" => "frodo"},
            presentation_breakdowns: frodo_presentation_breakdowns
          ),

          create(
            :cached_aggregation,
            organization:,
            charge:,
            external_subscription_id: subscription.external_id,
            timestamp: from_datetime - 2.days,
            current_aggregation: 2000,
            grouped_by: {"agent_name" => "aragorn"}
          )
        ]
      end

      before { cached_aggregations }

      it "uses the persisted recurring value as initial value" do
        result = aggregator.aggregate

        expect(result.aggregations.count).to eq(2)

        result.aggregations.sort_by { |a| a.grouped_by["agent_name"] }.each_with_index do |aggregation, index|
          expect(aggregation.aggregation.to_s).to eq("1000.0")
          expect(aggregation.count).to eq(0)
          expect(aggregation.variation).to eq(0)
          expect(aggregation.total_aggregated_units).to eq(1000)
          expect(aggregation.grouped_by["agent_name"]).to eq(agent_names[index])
          expect(aggregation.recurring_updated_at).to eq(from_datetime)
        end
      end

      context "when using presentation_by" do
        let(:presentation_by) { ["region"] }

        let(:events_values) do
          [
            {timestamp: Time.zone.parse("2023-08-01 00:00:00.000"), value: 2, agent_name: "aragorn", region: "eu"},
            {timestamp: Time.zone.parse("2023-08-01 01:00:00"), value: 3, agent_name: "frodo", region: "us"}
          ]
        end

        it "returns breakdowns per presentation group within each grouped_by group" do
          result = aggregator.aggregate

          expect(result.breakdowns.map { |breakdown| {groups: breakdown[:groups], value: breakdown[:value].round(5).to_s} }).to match_array(
            [
              {groups: {"agent_name" => "aragorn", "region" => "eu"}, value: "2.0"},
              {groups: {"agent_name" => "frodo", "region" => "us"}, value: "2.99597"}
            ]
          )
          expect(result.recurring_breakdowns).to match_array(
            [
              {groups: {"agent_name" => "aragorn", "region" => "eu"}, value: 2},
              {groups: {"agent_name" => "frodo", "region" => "us"}, value: 3}
            ]
          )
        end

        context "when frodo has cached presentation breakdowns" do
          let(:frodo_presentation_breakdowns) do
            [
              {"groups" => {"agent_name" => "frodo", "region" => "us"}, "value" => "100.0"}
            ]
          end

          it "uses frodo cached presentation breakdowns as initial values" do
            result = aggregator.aggregate

            expect(result.breakdowns.map { |breakdown| {groups: breakdown[:groups], value: breakdown[:value].round(5).to_s} }).to match_array(
              [
                {groups: {"agent_name" => "aragorn", "region" => "eu"}, value: "2.0"},
                {groups: {"agent_name" => "frodo", "region" => "us"}, value: "102.99597"}
              ]
            )
            expect(result.recurring_breakdowns).to match_array(
              [
                {groups: {"agent_name" => "aragorn", "region" => "eu"}, value: 2},
                {groups: {"agent_name" => "frodo", "region" => "us"}, value: 103}
              ]
            )
          end
        end

        context "when the cached presentation breakdowns are stored without the grouped_by keys" do
          let(:frodo_presentation_breakdowns) do
            [
              {"groups" => {"region" => "us"}, "value" => "100.0"}
            ]
          end

          it "matches them to their group" do
            result = aggregator.aggregate

            expect(result.breakdowns.map { |breakdown| {groups: breakdown[:groups], value: breakdown[:value].round(5).to_s} }).to match_array(
              [
                {groups: {"agent_name" => "aragorn", "region" => "eu"}, value: "2.0"},
                {groups: {"agent_name" => "frodo", "region" => "us"}, value: "102.99597"}
              ]
            )
            expect(result.recurring_breakdowns).to match_array(
              [
                {groups: {"agent_name" => "aragorn", "region" => "eu"}, value: 2},
                {groups: {"agent_name" => "frodo", "region" => "us"}, value: 103}
              ]
            )
          end
        end

        context "when aragorn has cached presentation breakdowns" do
          let(:aragorn_presentation_breakdowns) do
            [
              {"groups" => {"agent_name" => "aragorn", "region" => "eu"}, "value" => "100.0"}
            ]
          end

          it "uses aragorn cached presentation breakdowns as initial values" do
            result = aggregator.aggregate

            expect(result.breakdowns.map { |breakdown| {groups: breakdown[:groups], value: breakdown[:value].round(5).to_s} }).to match_array(
              [
                {groups: {"agent_name" => "aragorn", "region" => "eu"}, value: "102.0"},
                {groups: {"agent_name" => "frodo", "region" => "us"}, value: "2.99597"}
              ]
            )
          end
        end
      end

      context "with snapshots of the previous period" do
        let(:initial_value) do
          [snapshot(units: 400, grouped_by: {"agent_name" => "aragorn"}), snapshot(units: 600, grouped_by: {"agent_name" => "frodo"})]
        end

        it "uses the snapshots as initial values" do
          result = aggregator.aggregate

          expect(result.aggregations.map { [it.grouped_by, it.aggregation, it.total_aggregated_units, it.recurring_units] }).to match_array(
            [
              [{"agent_name" => "aragorn"}, 400, 400, 400],
              [{"agent_name" => "frodo"}, 600, 600, 600]
            ]
          )
        end

        context "when using presentation_by" do
          let(:presentation_by) { ["region"] }
          let(:initial_value) do
            [
              snapshot(
                units: 400,
                grouped_by: {"agent_name" => "aragorn"},
                presentation_breakdowns: [{"groups" => {"region" => "eu"}, "value" => "400.0"}]
              ),
              snapshot(
                units: 600,
                grouped_by: {"agent_name" => "frodo"},
                presentation_breakdowns: [{"groups" => {"region" => "us"}, "value" => "600.0"}]
              )
            ]
          end

          it "matches the snapshot presentation breakdowns to their group" do
            result = aggregator.aggregate

            expect(result.breakdowns.map { |breakdown| {groups: breakdown[:groups], value: breakdown[:value].round(5).to_s} }).to match_array(
              [
                {groups: {"agent_name" => "aragorn", "region" => "eu"}, value: "400.0"},
                {groups: {"agent_name" => "frodo", "region" => "us"}, value: "600.0"}
              ]
            )
            expect(result.recurring_breakdowns).to match_array(
              [
                {groups: {"agent_name" => "aragorn", "region" => "eu"}, value: 400},
                {groups: {"agent_name" => "frodo", "region" => "us"}, value: 600}
              ]
            )
          end
        end

        context "when no group had active units at the end of the previous period" do
          let(:initial_value) { [] }
          let(:events_values) { [{timestamp: from_datetime, value: 2, agent_name: "aragorn"}] }

          it "starts every group from zero" do
            expect(aggregator.aggregate.aggregations.map { [it.grouped_by, it.total_aggregated_units, it.recurring_units] })
              .to eq([[{"agent_name" => "aragorn"}, 2, 2]])
          end
        end

        context "when the snapshots close an older period" do
          let(:snapshot_to_datetime) { from_datetime - 1.month - 1.second }
          let(:initial_value) do
            [
              snapshot(
                units: 400,
                grouped_by: {"agent_name" => "aragorn"},
                to_datetime: snapshot_to_datetime,
                presentation_breakdowns: [{"groups" => {"region" => "eu"}, "value" => "400.0"}]
              )
            ]
          end
          let(:events_values) do
            [
              {timestamp: from_datetime - 10.days, value: 3, agent_name: "aragorn", region: "eu"},
              {timestamp: from_datetime - 5.days, value: 5, agent_name: "frodo", region: "us"}
            ]
          end

          it "adds the events dated after the snapshot period to each group" do
            # aragorn: 400 snapshot + 3 unbilled; frodo: no snapshot + 5 unbilled
            expect(aggregator.aggregate.aggregations.map { [it.grouped_by, it.total_aggregated_units] }).to match_array(
              [[{"agent_name" => "aragorn"}, 403], [{"agent_name" => "frodo"}, 5]]
            )
          end

          context "when using presentation_by" do
            let(:presentation_by) { ["region"] }

            it "adds them to the snapshot presentation breakdowns" do
              # aragorn/eu: 400 + 3, frodo/us: 0 + 5
              expect(aggregator.aggregate.recurring_breakdowns).to match_array(
                [
                  {groups: {"agent_name" => "aragorn", "region" => "eu"}, value: 403},
                  {groups: {"agent_name" => "frodo", "region" => "us"}, value: 5}
                ]
              )
            end
          end
        end

        context "with ClickHouse events", clickhouse: true do
          let(:event_store_class) { Events::Stores::ClickhouseStore }
          let(:organization) { create(:organization, clickhouse_events_store: true) }
          let(:subscription) { create(:subscription, organization:, started_at: DateTime.parse("2023-04-01 22:22:22")) }
          let(:initial_value) do
            [snapshot(units: 400, grouped_by: {"agent_name" => "aragorn"}), snapshot(units: 600, grouped_by: {"agent_name" => nil})]
          end

          before do
            create(:clickhouse_events_enriched, organization:, subscription:, customer:, billable_metric:,
              timestamp: from_datetime, properties: {"agent_name" => "aragorn"}, value: "2", decimal_value: 2)
            create(:clickhouse_events_enriched, organization:, subscription:, customer:, billable_metric:,
              timestamp: from_datetime, value: "5", decimal_value: 5)
          end

          it "matches the snapshots to their group, the null one included" do
            expect(aggregator.aggregate.aggregations.map { [it.grouped_by, it.aggregation, it.total_aggregated_units, it.recurring_units] }).to match_array(
              [
                [{"agent_name" => "aragorn"}, 402, 402, 402],
                [{"agent_name" => nil}, 605, 605, 605]
              ]
            )
          end
        end
      end

      context "when the previous period is closed but not invoiced yet" do
        let(:events_values) { [{timestamp: from_datetime - 10.days, value: 3, agent_name: "aragorn", region: "eu"}] }
        let(:cached_aggregations) do
          {"aragorn" => "eu", "frodo" => "us"}.map do |agent_name, region|
            create(:cached_aggregation, organization:, charge:, external_subscription_id: subscription.external_id,
              timestamp: from_datetime - 1.month - 1.day, current_aggregation: 1000, grouped_by: {"agent_name" => agent_name},
              presentation_breakdowns: [{"groups" => {"region" => region}, "value" => "1000.0"}],
              created_at: from_datetime - 1.month + 10.minutes)
          end
        end

        before do
          create(:invoice_subscription, subscription:, invoicing_reason: :subscription_periodic,
            charges_from_datetime: from_datetime - 2.months, charges_to_datetime: from_datetime - 1.month - 1.second)
        end

        context "when only a progressive billing invoice wrote cached aggregations" do
          let(:cached_aggregations) do
            create(:cached_aggregation, organization:, charge:, external_subscription_id: subscription.external_id,
              timestamp: from_datetime - 10.days, current_aggregation: 3, grouped_by: {"agent_name" => "aragorn"},
              created_at: from_datetime - 5.days)
          end

          it "starts every group from zero and adds the events of the unbilled period" do
            # aragorn: no invoiced level + 3 unbilled, already in the progressive row
            expect(aggregator.aggregate.aggregations.map { [it.grouped_by, it.total_aggregated_units] })
              .to eq([[{"agent_name" => "aragorn"}, 3]])
          end
        end

        it "adds the events of the unbilled period to each group" do
          # aragorn: 1000 cached + 3 unbilled; frodo: 1000 cached
          expect(aggregator.aggregate.aggregations.map { [it.grouped_by, it.total_aggregated_units] }).to match_array(
            [[{"agent_name" => "aragorn"}, 1003], [{"agent_name" => "frodo"}, 1000]]
          )
        end

        context "when using presentation_by" do
          let(:presentation_by) { ["region"] }

          it "adds them to the cached presentation breakdowns" do
            expect(aggregator.aggregate.recurring_breakdowns).to match_array(
              [
                {groups: {"agent_name" => "aragorn", "region" => "eu"}, value: 1003},
                {groups: {"agent_name" => "frodo", "region" => "us"}, value: 1000}
              ]
            )
          end
        end
      end

      context "without cached aggregation events" do
        let(:cached_aggregations) {}

        it "returns an empty result" do
          result = aggregator.aggregate

          expect(result.aggregations.count).to eq(1)

          aggregation = result.aggregations.first
          expect(aggregation.aggregation).to eq(0)
          expect(aggregation.count).to eq(0)
          expect(aggregation.grouped_by).to eq({"agent_name" => nil})
        end

        context "with events attached to a previous subcription" do
          let(:previous_subscription) do
            create(
              :subscription,
              :terminated,
              started_at: DateTime.parse("2022-01-01 22:22:22"),
              terminated_at: DateTime.parse("2023-04-01 22:22:21")
            )
          end

          let(:customer) { previous_subscription.customer }

          let(:subscription) do
            create(
              :subscription,
              started_at: DateTime.parse("2023-04-01 22:22:22"),
              previous_subscription:,
              customer:,
              external_id: previous_subscription.external_id
            )
          end

          before do
            subscription

            create(
              :event,
              organization_id: organization.id,
              code: billable_metric.code,
              subscription: previous_subscription,
              customer:,
              timestamp: Time.zone.parse("2023-03-01 22:22:22"),
              properties: {value: 10, agent_name: "aragorn", region: "eu"}
            )

            create(
              :event,
              organization_id: organization.id,
              code: billable_metric.code,
              subscription: previous_subscription,
              customer:,
              timestamp: Time.zone.parse("2023-03-01 22:22:22"),
              properties: {value: 10, agent_name: "frodo", region: "us"}
            )
          end

          it "uses previous events as latest value" do
            result = aggregator.aggregate

            expect(result.aggregations.count).to eq(2)

            result.aggregations.sort_by { |a| a.grouped_by["agent_name"] }.each_with_index do |aggregation, index|
              expect(aggregation.aggregation.to_s).to eq("10.0")
              expect(aggregation.count).to eq(0)
              expect(aggregation.variation).to eq(0)
              expect(aggregation.total_aggregated_units).to eq(10)
              expect(aggregation.grouped_by["agent_name"]).to eq(agent_names[index])
              expect(aggregation.recurring_updated_at).to eq(from_datetime)
            end
          end

          context "when using presentation_by" do
            let(:presentation_by) { ["region"] }

            it "returns previous events as presentation breakdowns" do
              result = aggregator.aggregate

              expect(result.breakdowns.map { |breakdown| {groups: breakdown[:groups], value: breakdown[:value].round(5).to_s} }).to match_array(
                [
                  {groups: {"agent_name" => "aragorn", "region" => "eu"}, value: "10.0"},
                  {groups: {"agent_name" => "frodo", "region" => "us"}, value: "10.0"}
                ]
              )
            end
          end
        end
      end

      context "with events" do
        let(:events_values) do
          [
            {timestamp: DateTime.parse("2023-08-01 00:00:00.000"), value: 2, agent_name: "aragorn", region: "eu"},
            {timestamp: DateTime.parse("2023-08-01 01:00:00"), value: 3, agent_name: "aragorn", region: "eu"},
            {timestamp: DateTime.parse("2023-08-01 01:30:00"), value: 1, agent_name: "aragorn", region: "eu"},
            {timestamp: DateTime.parse("2023-08-01 02:00:00"), value: -4, agent_name: "aragorn", region: "eu"},
            {timestamp: DateTime.parse("2023-08-01 04:00:00"), value: -2, agent_name: "aragorn", region: "eu"},
            {timestamp: DateTime.parse("2023-08-01 05:00:00"), value: 10, agent_name: "aragorn", region: "eu"},
            {timestamp: DateTime.parse("2023-08-01 05:30:00"), value: -10, agent_name: "aragorn", region: "eu"},

            {timestamp: DateTime.parse("2023-08-01 00:00:00.000"), value: 2, agent_name: "frodo", region: "us"},
            {timestamp: DateTime.parse("2023-08-01 01:00:00"), value: 3, agent_name: "frodo", region: "us"},
            {timestamp: DateTime.parse("2023-08-01 01:30:00"), value: 1, agent_name: "frodo", region: "us"},
            {timestamp: DateTime.parse("2023-08-01 02:00:00"), value: -4, agent_name: "frodo", region: "us"},
            {timestamp: DateTime.parse("2023-08-01 04:00:00"), value: -2, agent_name: "frodo", region: "us"},
            {timestamp: DateTime.parse("2023-08-01 05:00:00"), value: 10, agent_name: "frodo", region: "us"},
            {timestamp: DateTime.parse("2023-08-01 05:30:00"), value: -10, agent_name: "frodo", region: "us"}
          ]
        end

        it "aggregates the events" do
          result = aggregator.aggregate

          expect(result.aggregations.count).to eq(2)

          result.aggregations.sort_by { |a| a.grouped_by["agent_name"] }.each_with_index do |aggregation, index|
            expect(aggregation.aggregation.round(5).to_s).to eq("1000.02218")
            expect(aggregation.count).to eq(7)
            expect(aggregation.variation).to eq(0)
            expect(aggregation.total_aggregated_units).to eq(1000)
            expect(aggregation.grouped_by["agent_name"]).to eq(agent_names[index])
            expect(aggregation.recurring_updated_at).to eq("2023-08-01 05:30:00")
          end
        end

        context "when using presentation_by" do
          let(:presentation_by) { ["region"] }
          let(:aragorn_presentation_breakdowns) do
            [
              {"groups" => {"agent_name" => "aragorn", "region" => "eu"}, "value" => "100.0"}
            ]
          end
          let(:frodo_presentation_breakdowns) do
            [
              {"groups" => {"agent_name" => "frodo", "region" => "us"}, "value" => "200.0"}
            ]
          end

          it "uses cached presentation breakdowns as initial values" do
            result = aggregator.aggregate

            expect(result.breakdowns.map { |breakdown| {groups: breakdown[:groups], value: breakdown[:value].round(5).to_s} }).to match_array(
              [
                {groups: {"agent_name" => "aragorn", "region" => "eu"}, value: "100.02218"},
                {groups: {"agent_name" => "frodo", "region" => "us"}, value: "200.02218"}
              ]
            )
            expect(result.recurring_breakdowns).to match_array(
              [
                {groups: {"agent_name" => "aragorn", "region" => "eu"}, value: 100},
                {groups: {"agent_name" => "frodo", "region" => "us"}, value: 200}
              ]
            )
          end

          context "when cached presentation breakdowns are empty" do
            let(:aragorn_presentation_breakdowns) { [] }
            let(:frodo_presentation_breakdowns) { [] }

            it "returns current events as presentation breakdowns" do
              result = aggregator.aggregate

              expect(result.breakdowns.map { |breakdown| {groups: breakdown[:groups], value: breakdown[:value].round(5).to_s} }).to match_array(
                [
                  {groups: {"agent_name" => "aragorn", "region" => "eu"}, value: "0.02218"},
                  {groups: {"agent_name" => "frodo", "region" => "us"}, value: "0.02218"}
                ]
              )
            end
          end
        end
      end
    end

    context "with filters" do
      let(:matching_filters) { {region: ["europe"]} }

      let(:events_values) do
        [
          {
            timestamp: DateTime.parse("2023-08-01 00:00:00.000"),
            value: 1000,
            region: "europe",
            agent_name: "aragorn"
          },
          {timestamp: DateTime.parse("2023-08-01 00:00:00.000"), value: 1000, region: "europe", agent_name: "frodo"}
        ]
      end

      it "aggregates the events" do
        result = aggregator.aggregate

        expect(result.aggregations.count).to eq(2)

        result.aggregations.sort_by { |a| a.grouped_by["agent_name"] }.each_with_index do |aggregation, _index|
          expect(aggregation.aggregation.round(5).to_s).to eq("1000.0")
          expect(aggregation.count).to eq(1)
        end
      end
    end
  end
end
