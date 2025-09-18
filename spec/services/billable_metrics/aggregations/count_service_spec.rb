# frozen_string_literal: true

require "rails_helper"

RSpec.describe BillableMetrics::Aggregations::CountService do
  subject(:count_service) do
    described_class.new(
      event_store_class:,
      charge:,
      subscription:,
      boundaries: {
        from_datetime:,
        to_datetime:
      },
      filters:,
      bypass_aggregation:
    )
  end

  let(:event_store_class) { Events::Stores::PostgresStore }
  let(:bypass_aggregation) { false }
  let(:filters) do
    {event: pay_in_advance_event, grouped_by:, matching_filters:, ignored_filters:}
  end

  let(:subscription) { create(:subscription) }
  let(:organization) { subscription.organization }
  let(:customer) { subscription.customer }
  let(:grouped_by) { nil }
  let(:matching_filters) { {} }
  let(:ignored_filters) { [] }

  let(:billable_metric) do
    create(
      :billable_metric,
      organization:,
      aggregation_type: "count_agg"
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

  let(:pay_in_advance_event) { nil }

  let(:event_list) do
    create_list(
      :event,
      4,
      organization_id: organization.id,
      code: billable_metric.code,
      subscription:,
      customer:,
      timestamp: Time.zone.now - 1.day
    )
  end

  before do
    event_list
  end

  it "aggregates the events" do
    result = count_service.aggregate

    expect(result.aggregation).to eq(4)
  end

  context "when events are out of bounds" do
    let(:to_datetime) { Time.zone.now - 2.days }

    it "does not take events into account" do
      result = count_service.aggregate

      expect(result.aggregation).to eq(0)
    end
  end

  context "when filters are given" do
    let(:matching_filters) { {cloud: ["AWS"], region: ["europe"]} }

    let(:event_list) do
      [
        create(
          :event,
          organization_id: organization.id,
          code: billable_metric.code,
          customer:,
          subscription:,
          timestamp: Time.zone.now - 1.day,
          properties: {
            total_count: 12,
            cloud: "AWS",
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
            total_count: 8,
            cloud: "AWS",
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
            cloud: "AWS",
            region: "africa"
          }
        )
      ]
    end

    it "aggregates the events" do
      result = count_service.aggregate

      expect(result.aggregation).to eq(2)
    end
  end

  context "when pay_in_advance aggregation" do
    let(:pay_in_advance_event) { create(:event, subscription_id: subscription.id, customer_id: customer.id) }

    it "assigns an pay_in_advance aggregation" do
      result = count_service.aggregate

      expect(result.pay_in_advance_aggregation).to eq(1)
    end
  end

  context "when bypass_aggregation is set to true" do
    let(:bypass_aggregation) { true }

    it "returns a default empty result" do
      result = count_service.aggregate

      expect(result.aggregation).to eq(0)
      expect(result.count).to eq(0)
      expect(result.current_usage_units).to eq(0)
      expect(result.options).to eq({running_total: []})
    end
  end

  describe ".per_event_aggregation" do
    it "aggregates per events" do
      result = count_service.per_event_aggregation

      expect(result.event_aggregation).to eq([1, 1, 1, 1])
    end

    context "with grouped_by_values" do
      before do
        event_list.first.update!(properties: {"scheme" => "visa"})
      end

      it "takes the groups into account" do
        result = count_service.per_event_aggregation(grouped_by_values: {"scheme" => "visa"})

        expect(result.event_aggregation).to eq([1])
      end
    end
  end

  describe ".grouped_by_aggregation" do
    let(:grouped_by) { ["agent_name"] }
    let(:agent_names) { %w[aragorn frodo gimli legolas] }

    let(:event_list) do
      agent_names.map do |agent_name|
        create(
          :event,
          organization_id: organization.id,
          code: billable_metric.code,
          customer:,
          subscription:,
          timestamp: Time.zone.now - 1.day,
          properties: {
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
          properties: {}
        )
      ]
    end

    it "returns a grouped aggregations" do
      result = count_service.aggregate

      expect(result.aggregations.count).to eq(5)

      result.aggregations.sort_by { |a| a.grouped_by["agent_name"] || "" }.each_with_index do |aggregation, index|
        expect(aggregation.aggregation).to eq(1)
        expect(aggregation.count).to eq(1)
        expect(aggregation.current_usage_units).to eq(1)

        expect(aggregation.grouped_by["agent_name"]).to eq(agent_names[index - 1]) if index.positive?
        expect(aggregation.options[:running_total]).to eq([])
      end
    end

    context "without events" do
      let(:event_list) { [] }

      it "returns an empty result" do
        result = count_service.aggregate

        expect(result.aggregations.count).to eq(1)

        aggregation = result.aggregations.first
        expect(aggregation.aggregation).to eq(0)
        expect(aggregation.count).to eq(0)
        expect(aggregation.grouped_by).to eq({"agent_name" => nil})
      end
    end

    context "with free units per events" do
      it "returns a result with free units" do
        result = count_service.aggregate(options: {free_units_per_events: 10})

        expect(result.aggregations.count).to eq(5)

        result.aggregations.each_with_index do |aggregation, index|
          expect(aggregation.options[:running_total]).to eq([1])
        end
      end
    end

    context "when bypass_aggregation is set to true" do
      let(:bypass_aggregation) { true }

      it "returns an empty result" do
        result = count_service.aggregate

        expect(result.aggregations.count).to eq(1)

        aggregation = result.aggregations.first
        expect(aggregation.aggregation).to eq(0)
        expect(aggregation.count).to eq(0)
        expect(aggregation.grouped_by).to eq({"agent_name" => nil})
      end
    end
  end
end
