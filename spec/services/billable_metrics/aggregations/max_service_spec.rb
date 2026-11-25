# frozen_string_literal: true

require "rails_helper"

RSpec.describe BillableMetrics::Aggregations::MaxService do
  subject(:max_service) do
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
  let(:subscription) { create(:subscription) }
  let(:customer) { subscription.customer }
  let(:grouped_by) { nil }
  let(:presentation_by) { nil }
  let(:matching_filters) { {} }
  let(:ignored_filters) { [] }
  let(:billable_metric) do
    create(
      :billable_metric,
      organization:,
      aggregation_type: "max_agg",
      field_name: "total_count"
    )
  end
  let(:charge) do
    create(
      :standard_charge,
      billable_metric:
    )
  end
  let(:from_datetime) { (Time.current - 1.month).beginning_of_day }
  let(:to_datetime) { Time.current.end_of_day }
  let(:events) do
    [
      create_list(
        :event,
        4,
        organization_id: organization.id,
        code: billable_metric.code,
        customer:,
        subscription:,
        timestamp: Time.zone.now - 2.days,
        properties: {
          total_count: rand(10)
        }
      ),

      create(
        :event,
        organization_id: organization.id,
        code: billable_metric.code,
        customer:,
        subscription:,
        timestamp: Time.zone.now - 1.day,
        properties: {
          total_count: 12
        }
      )
    ].flatten
  end
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
  let(:filters) { {grouped_by:, presentation_by:, matching_filters:, ignored_filters:} }

  let_it_be(:organization) { create_default(:organization) }

  before { events }

  it "aggregates the events" do
    result = max_service.aggregate

    expect(result.aggregation).to eq(12)
    expect(result.count).to eq(5)
  end

  context "when the event store fails and the metric uses rounding" do
    let(:events) { [] }
    let(:billable_metric) do
      create(:billable_metric, organization:, aggregation_type: :max_agg, field_name: "total_count", rounding_function: "floor", rounding_precision: 0)
    end

    before { allow(event_store).to receive(:max).and_raise(ActiveRecord::StatementInvalid, "store unavailable") }

    it "returns the aggregation failure" do
      result = max_service.aggregate

      expect(result).to be_failure
      expect(result.error.code).to eq("aggregation_failure")
    end
  end

  context "when an earlier segment has a higher peak" do
    let(:cycle_usage_tracker) { instance_double(Fees::ChargeService::Trackers::CycleClosingUnits, apply_closing_values?: true, apply_carry_over?: false, carryover_variation?: false) }
    let(:billable_metric) do
      create(:billable_metric, organization:, aggregation_type: :max_agg, field_name: "total_count", rounding_function: "floor", rounding_precision: 0)
    end
    let(:events) do
      [create(:event, organization_id: organization.id, subscription:, code: billable_metric.code,
        timestamp: to_datetime - 1.day, properties: {total_count: 3})]
    end

    before do
      allow(cycle_usage_tracker).to receive(:each_closing_value) do |groups:, **, &block|
        block.call(groups.sole, BigDecimal("10.9"), nil)
      end
    end

    it "keeps the local maximum and event count while pricing the rounded closing units" do
      result = max_service.aggregate(cycle_usage_tracker:)
      expect(result).to have_attributes(aggregation: 3, count: 1, closing_units: 10)
      price = ChargeModels::StandardService.apply(pricing_structure: metered_item.pricing_structure, aggregation_result: result)
      expect(price.units).to eq(10)
    end
  end

  context "when events are out of bounds" do
    let(:to_datetime) { Time.zone.now - 3.days }

    it "does not take events into account" do
      result = max_service.aggregate

      expect(result.aggregation).to eq(0)
      expect(result.count).to eq(0)
    end
  end

  context "when bypass_aggregation is set to true" do
    let(:bypass_aggregation) { true }

    it "returns a default empty result" do
      result = max_service.aggregate

      expect(result.aggregation).to eq(0)
      expect(result.count).to eq(0)
      expect(result.current_usage_units).to eq(0)
      expect(result.options).to eq({running_total: []})
    end
  end

  context "when properties is not found on events" do
    before do
      billable_metric.update!(field_name: "foo_bar")
    end

    it "counts as zero" do
      result = max_service.aggregate

      expect(result.aggregation).to eq(0)
      expect(result.count).to eq(0)
    end
  end

  context "when properties is a float" do
    let(:events) do
      [
        create(
          :event,
          organization_id: organization.id,
          code: billable_metric.code,
          customer:,
          subscription:,
          timestamp: Time.zone.now - 1.day,
          properties: {
            total_count: 14.2
          }
        )
      ]
    end

    it "aggregates the events" do
      result = max_service.aggregate

      expect(result.aggregation).to eq(14.2)
    end
  end

  context "when properties is not a number" do
    let(:events) do
      [
        create(
          :event,
          organization_id: organization.id,
          code: billable_metric.code,
          customer:,
          subscription:,
          timestamp: Time.zone.now - 1.day,
          properties: {
            total_count: "foo_bar"
          }
        )
      ]
    end

    it "ignores the event" do
      result = max_service.aggregate

      expect(result).to be_success
      expect(result.aggregation).to eq(0)
      expect(result.count).to eq(0)
    end
  end

  context "when properties is missing" do
    let(:events) do
      [
        create(
          :event,
          organization_id: organization.id,
          code: billable_metric.code,
          customer:,
          subscription:,
          timestamp: Time.zone.now - 1.day
        )
      ]
    end

    it "ignore the event" do
      result = max_service.aggregate

      expect(result).to be_success
      expect(result.count).to eq(0)
      expect(result.aggregation).to eq(0)
    end
  end

  context "when filters are given" do
    let(:matching_filters) { {region: ["europe"]} }

    let(:events) do
      [
        create(
          :event,
          organization_id: organization.id,
          code: billable_metric.code,
          customer:,
          subscription:,
          timestamp: Time.zone.now - 1.day,
          properties: {
            total_count: 8,
            region: "europe"
          }
        ),

        create(
          :event,
          organization_id: organization.id,
          code: billable_metric.code,
          customer:,
          subscription:,
          timestamp: Time.zone.now - 1.day,
          properties: {
            total_count: 12,
            region: "africa"
          }
        )
      ]
    end

    it "aggregates the events" do
      result = max_service.aggregate

      expect(result.aggregation).to eq(8)
      expect(result.count).to eq(1)
    end
  end

  describe ".per_event_aggregation" do
    it "aggregates per events" do
      result = max_service.per_event_aggregation

      expect(result.event_aggregation).to eq([0, 0, 0, 0, 12])
    end

    context "with grouped_by_values" do
      let(:event) { events.first }

      before do
        event.update!(properties: event.properties.merge(scheme: "visa"))
      end

      it "takes the groups into account" do
        result = max_service.per_event_aggregation(grouped_by_values: {"scheme" => "visa"})

        expect(result.event_aggregation).to eq([event.properties["total_count"]])
      end
    end

    context "with closing units" do
      let(:values) { [-3, 0] }
      let(:events) do
        values.each_with_index.map do |value, index|
          create(:event, organization_id: organization.id, code: billable_metric.code, customer:, subscription:,
            timestamp: to_datetime - 1.day + index.minutes, properties: {total_count: value})
        end
      end

      it "keeps the closing value on the zero maximum's event" do
        expect(max_service.per_event_aggregation(closing_units: 10).event_aggregation).to eq([0, 10])
        expect(max_service.per_event_aggregation.event_aggregation).to eq([0, 0])
      end

      context "when the local maximum is negative" do
        let(:values) { [-3, -5] }

        it "keeps the closing value on the negative maximum's event" do
          expect(max_service.per_event_aggregation(closing_units: 10).event_aggregation).to eq([10, 0])
        end
      end

      context "with duplicate maxima" do
        let(:values) { [3, 3] }

        it "uses the first maximum only" do
          expect(max_service.per_event_aggregation(closing_units: 10).event_aggregation).to eq([10, 0])
        end
      end

      context "when the closing value is zero" do
        let(:values) { [3, 5] }

        it "does not fall back to the local maximum" do
          expect(max_service.per_event_aggregation(closing_units: 0).event_aggregation).to eq([0, 0])
        end
      end

      context "without events" do
        let(:values) { [] }

        it "does not create an event for the closing value" do
          expect(max_service.per_event_aggregation(closing_units: 10).event_aggregation).to eq([])
        end
      end

      context "when aggregation is bypassed" do
        let(:bypass_aggregation) { true }

        it "keeps the result empty" do
          expect(max_service.per_event_aggregation(closing_units: 10).event_aggregation).to eq([])
        end
      end

      context "with pricing groups" do
        let(:events) do
          [[-3, "EU"], [0, "EU"], [4, "US"], [8, "US"]].each_with_index.map do |(value, region), index|
            create(:event, organization_id: organization.id, code: billable_metric.code, customer:, subscription:,
              timestamp: to_datetime - 1.day + index.minutes, properties: {total_count: value, region:})
          end
        end

        it "does not retain another group's closing value or filter" do
          expect(max_service.per_event_aggregation(grouped_by_values: {"region" => "EU"}, closing_units: 10).event_aggregation).to eq([0, 10])
          expect(max_service.per_event_aggregation(grouped_by_values: {"region" => "US"}, closing_units: 20).event_aggregation).to eq([0, 20])
          expect(max_service.per_event_aggregation(grouped_by_values: {"region" => "EU"}, closing_units: 12).event_aggregation).to eq([0, 12])
        end
      end

      context "with ClickHouse events", clickhouse: true do
        let(:event_store_class) { Events::Stores::ClickhouseStore }

        before do
          events.each do |event|
            value = event.properties.fetch("total_count")
            create(:clickhouse_events_enriched, organization:, subscription:, customer:, billable_metric:,
              timestamp: event.timestamp, properties: event.properties, value: value.to_s, decimal_value: value)
          end
        end

        it "keeps the closing value on the zero maximum's event" do
          expect(max_service.per_event_aggregation(closing_units: 10).event_aggregation).to eq([0, 10])
        end

        context "with duplicate maxima" do
          let(:values) { [3, 3] }

          it "uses the first maximum only" do
            expect(max_service.per_event_aggregation(closing_units: 10).event_aggregation).to eq([10, 0])
          end
        end
      end
    end
  end

  describe ".grouped_by_aggregation" do
    let(:grouped_by) { ["agent_name"] }
    let(:agent_names) { %w[aragorn frodo gimli legolas] }

    let(:events) do
      agent_names.map do |agent_name|
        create(
          :event,
          organization_id: organization.id,
          code: billable_metric.code,
          customer:,
          subscription:,
          timestamp: Time.zone.now - 1.day,
          properties: {
            total_count: 12,
            agent_name:
          }
        )
      end + [
        create(
          :event,
          organization_id: organization.id,
          code: billable_metric.code,
          customer:,
          subscription:,
          timestamp: Time.zone.now - 1.day,
          properties: {
            total_count: 12
          }
        )
      ]
    end

    it "returns a grouped aggregations" do
      result = max_service.aggregate

      expect(result.aggregations.count).to eq(5)

      result.aggregations.sort_by { |a| a.grouped_by["agent_name"] || "" }.each_with_index do |aggregation, index|
        expect(aggregation.aggregation).to eq(12)
        expect(aggregation.count).to eq(1)

        expect(aggregation.grouped_by["agent_name"]).to eq(agent_names[index - 1]) if index.positive?
      end
    end

    context "without events" do
      let(:events) { [] }

      it "returns an empty result" do
        result = max_service.aggregate

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
        result = max_service.aggregate

        expect(result.aggregations.count).to eq(1)

        aggregation = result.aggregations.first
        expect(aggregation.aggregation).to eq(0)
        expect(aggregation.count).to eq(0)
        expect(aggregation.grouped_by).to eq({"agent_name" => nil})
      end
    end
  end

  context "with presentation group keys" do
    let(:presentation_by) { ["cloud"] }

    let(:events) do
      [
        create_list(
          :event,
          3,
          organization_id: organization.id,
          code: billable_metric.code,
          customer:,
          subscription:,
          timestamp: Time.zone.now - 1.day,
          properties: {total_count: 10, cloud: "aws"}
        ),
        create(
          :event,
          organization_id: organization.id,
          code: billable_metric.code,
          customer:,
          subscription:,
          timestamp: Time.zone.now - 1.day,
          properties: {total_count: 12, cloud: "gcp"}
        )
      ].flatten
    end

    it "returns the aggregations per group" do
      result = max_service.aggregate

      expect(result.breakdowns).to match_array([
        {groups: {"cloud" => "aws"}, value: 10},
        {groups: {"cloud" => "gcp"}, value: 12}
      ])
    end

    context "with grouped_by" do
      let(:grouped_by) { ["agent_name"] }

      let(:events) do
        [
          create(
            :event,
            organization_id: organization.id,
            code: billable_metric.code,
            customer:,
            subscription:,
            timestamp: Time.zone.now - 1.day,
            properties: {total_count: 2, agent_name: "frodo", cloud: "aws"}
          ),
          create(
            :event,
            organization_id: organization.id,
            code: billable_metric.code,
            customer:,
            subscription:,
            timestamp: Time.zone.now - 1.day,
            properties: {total_count: 7, agent_name: "frodo", cloud: "gcp"}
          ),
          create(
            :event,
            organization_id: organization.id,
            code: billable_metric.code,
            customer:,
            subscription:,
            timestamp: Time.zone.now - 1.day,
            properties: {total_count: 3, agent_name: "aragorn", cloud: "aws"}
          )
        ]
      end

      it "returns the aggregations per group" do
        result = max_service.aggregate

        expect(result.breakdowns).to match_array([
          {groups: {"agent_name" => "frodo", "cloud" => "aws"}, value: 2},
          {groups: {"agent_name" => "frodo", "cloud" => "gcp"}, value: 7},
          {groups: {"agent_name" => "aragorn", "cloud" => "aws"}, value: 3}
        ])
      end
    end
  end
end
