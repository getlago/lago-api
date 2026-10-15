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

  def create_previous_event(value:, **properties)
    create(
      :event,
      organization_id: organization.id,
      code: billable_metric.code,
      subscription:,
      customer:,
      timestamp: Time.zone.parse("2023-06-15 10:00:00"),
      properties: {value:, **properties}
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
    let(:initial_value) { [snapshot(units: 1000)] }

    it "uses the snapshot as initial value" do
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

      context "when the snapshot closes an older period" do
        let(:initial_value) { [snapshot(units: 400, to_datetime: from_datetime - 1.month)] }

        before { create_previous_event(value: 10) }

        it "reads the units carried over from the events" do
          expect(aggregator.aggregate.total_aggregated_units).to eq(10)
        end
      end

      context "when the snapshot closes after the period starts" do
        let(:initial_value) { [snapshot(units: 400, to_datetime: from_datetime + 1.second)] }

        before { create_previous_event(value: 10) }

        it "reads the units carried over from the events" do
          expect(aggregator.aggregate.total_aggregated_units).to eq(10)
        end
      end

      context "when the bucket had no active units at the end of the previous period" do
        let(:initial_value) { [] }
        let(:presentation_by) { ["region"] }

        before { create_previous_event(value: 10, region: "eu") }

        it "starts from zero units and breakdowns" do
          result = aggregator.aggregate

          expect([result.aggregation, result.total_aggregated_units, result.recurring_units, result.breakdowns]).to eq([0, 0, 0, []])
        end

        context "when the period is older" do
          let(:initial_period) { closed_period(from_datetime - 1.month) }

          it "reads the units carried over from the events" do
            expect(aggregator.aggregate.total_aggregated_units).to eq(10)
          end
        end
      end
    end

    context "when using presentation_by with no current events and zero initial value" do
      let(:presentation_by) { ["region"] }
      let(:events_values) { [] }
      let(:initial_value) do
        [snapshot(units: 0, presentation_breakdowns: [{groups: {"region" => "eu"}, value: "100.0"}])]
      end

      it "falls back to the snapshot presentation breakdowns" do
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

    context "without a snapshot" do
      let(:initial_value) { nil }

      it "falls back on 0" do
        result = aggregator.aggregate

        expect(result.aggregation.round(5).to_s).to eq("0.0")
        expect(result.count).to eq(0)
        expect(result.variation).to eq(0)
        expect(result.total_aggregated_units).to eq(0)
        expect(result.recurring_updated_at).to eq(from_datetime)
      end

      context "with events before the period" do
        before { create_previous_event(value: 10) }

        it "reads the units carried over from the events" do
          expect(aggregator.aggregate.total_aggregated_units).to eq(10)
        end

        context "when the period is the first of the subscription" do
          let(:subscription) { create(:subscription, started_at: from_datetime) }

          it "carries no units over" do
            expect(aggregator.aggregate.total_aggregated_units).to eq(0)
          end
        end
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

      let(:initial_value) do
        [
          snapshot(units: 1000, grouped_by: {"agent_name" => "aragorn"}, presentation_breakdowns: aragorn_presentation_breakdowns),
          snapshot(units: 1000, grouped_by: {"agent_name" => "frodo"}, presentation_breakdowns: frodo_presentation_breakdowns)
        ]
      end

      it "uses the snapshots as initial values" do
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

        context "when frodo has snapshot presentation breakdowns" do
          let(:frodo_presentation_breakdowns) do
            [
              {groups: {"agent_name" => "frodo", "region" => "us"}, value: "100.0"}
            ]
          end

          it "uses frodo snapshot presentation breakdowns as initial values" do
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

        context "when aragorn has snapshot presentation breakdowns" do
          let(:aragorn_presentation_breakdowns) do
            [
              {groups: {"agent_name" => "aragorn", "region" => "eu"}, value: "100.0"}
            ]
          end

          it "uses aragorn snapshot presentation breakdowns as initial values" do
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

        context "when no group had active units at the end of the previous period" do
          let(:initial_value) { [] }
          let(:events_values) { [{timestamp: from_datetime, value: 2, agent_name: "aragorn"}] }

          before { create_previous_event(value: 10, agent_name: "aragorn") }

          it "starts every group from zero" do
            expect(aggregator.aggregate.aggregations.map { [it.grouped_by, it.total_aggregated_units, it.recurring_units] })
              .to eq([[{"agent_name" => "aragorn"}, 2, 2]])
          end
        end

        context "when the snapshots close an older period" do
          let(:initial_value) do
            [snapshot(units: 400, grouped_by: {"agent_name" => "aragorn"}, to_datetime: from_datetime - 1.month)]
          end

          before do
            create_previous_event(value: 10, agent_name: "aragorn")
            create_previous_event(value: 20, agent_name: "frodo")
          end

          it "reads the units carried over from the events" do
            expect(aggregator.aggregate.aggregations.map { [it.grouped_by, it.total_aggregated_units] }).to match_array(
              [[{"agent_name" => "aragorn"}, 10], [{"agent_name" => "frodo"}, 20]]
            )
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

      context "without a snapshot" do
        let(:initial_value) { nil }

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
              {groups: {"agent_name" => "aragorn", "region" => "eu"}, value: "100.0"}
            ]
          end
          let(:frodo_presentation_breakdowns) do
            [
              {groups: {"agent_name" => "frodo", "region" => "us"}, value: "200.0"}
            ]
          end

          it "uses the snapshot presentation breakdowns as initial values" do
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

          context "when the snapshot presentation breakdowns are empty" do
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
