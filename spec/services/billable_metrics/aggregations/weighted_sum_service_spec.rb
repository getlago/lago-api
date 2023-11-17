# frozen_string_literal: true

require 'rails_helper'

RSpec.describe BillableMetrics::Aggregations::WeightedSumService, type: :service, transaction: false do
  subject(:aggregator) do
    described_class.new(
      event_store_class:,
      charge:,
      subscription:,
      group:,
      boundaries: {
        from_datetime:,
        to_datetime:,
        charges_duration:,
      },
    )
  end

  let(:event_store_class) { Events::Stores::PostgresStore }

  let(:subscription) { create(:subscription, started_at: DateTime.parse('2023-04-01 22:22:22')) }
  let(:organization) { subscription.organization }
  let(:customer) { subscription.customer }
  let(:group) { nil }

  let(:billable_metric) { create(:weighted_sum_billable_metric, organization:) }

  let(:charge) do
    create(
      :standard_charge,
      billable_metric:,
    )
  end

  let(:from_datetime) { Time.zone.parse('2023-08-01 00:00:00.000') }
  let(:to_datetime) { Time.zone.parse('2023-08-31 23:59:59.999') }
  let(:charges_duration) { 31 }

  let(:events_values) do
    [
      { timestamp: Time.zone.parse('2023-08-01 00:00:00.000'), value: 2 },
      { timestamp: Time.zone.parse('2023-08-01 01:00:00'), value: 3 },
      { timestamp: Time.zone.parse('2023-08-01 01:30:00'), value: 1 },
      { timestamp: Time.zone.parse('2023-08-01 02:00:00'), value: -4 },
      { timestamp: Time.zone.parse('2023-08-01 04:00:00'), value: -2 },
      { timestamp: Time.zone.parse('2023-08-01 05:00:00'), value: 10 },
      { timestamp: Time.zone.parse('2023-08-01 05:30:00'), value: -10 },
    ]
  end

  before do
    events_values.each do |values|
      properties = { value: values[:value] }
      properties[:region] = values[:region] if values[:region]

      create(
        :event,
        code: billable_metric.code,
        subscription:,
        customer:,
        timestamp: values[:timestamp],
        properties:,
      )
    end
  end

  it 'aggregates the events' do
    result = aggregator.aggregate

    expect(result.aggregation.round(5).to_s).to eq('0.02218')
    expect(result.count).to eq(7)
  end

  context 'with a single event' do
    let(:events_values) do
      [
        { timestamp: Time.zone.parse('2023-08-01 00:00:00.000'), value: 1000 },
      ]
    end

    it 'aggregates the events' do
      result = aggregator.aggregate

      expect(result.aggregation.round(5).to_s).to eq('1000.0')
      expect(result.count).to eq(1)
    end
  end

  context 'with no events' do
    let(:events_values) { [] }

    it 'aggregates the events' do
      result = aggregator.aggregate

      expect(result.aggregation.round(5).to_s).to eq('0.0')
      expect(result.count).to eq(0)
    end
  end

  context 'with events with the same timestamo' do
    let(:events_values) do
      [
        { timestamp: Time.zone.parse('2023-08-01 00:00:00.000'), value: 3 },
        { timestamp: Time.zone.parse('2023-08-01 00:00:00.000'), value: 3 },
      ]
    end

    it 'aggregates the events' do
      result = aggregator.aggregate

      expect(result.aggregation).to eq(6)
      expect(result.count).to eq(2)
    end
  end

  context 'when billable metric is recurring' do
    let(:billable_metric) { create(:weighted_sum_billable_metric, :recurring, organization:) }

    let(:events_values) { [] }

    let(:quantified_event) do
      create(
        :quantified_event,
        billable_metric:,
        external_subscription_id: subscription.external_id,
        added_at: from_datetime - 1.day,
        properties: { QuantifiedEvent::RECURRING_TOTAL_UNITS => 1000 },
      )
    end

    before { quantified_event }

    it 'uses the persisted recurring value as initial value' do
      result = aggregator.aggregate

      expect(result.aggregation.to_s).to eq('1000.0')
      expect(result.count).to eq(0)
      expect(result.variation).to eq(0)
      expect(result.total_aggregated_units).to eq(1000)
      expect(result.recurring_updated_at).to eq(from_datetime)
    end

    context 'without quantified events' do
      let(:quantified_event) {}

      it 'falls back on 0' do
        result = aggregator.aggregate

        expect(result.aggregation.round(5).to_s).to eq('0.0')
        expect(result.count).to eq(0)
        expect(result.variation).to eq(0)
        expect(result.total_aggregated_units).to eq(0)
        expect(result.recurring_updated_at).to eq(from_datetime)
      end

      context 'with events attached to a previous subcription' do
        let(:previous_subscription) do
          create(
            :subscription,
            :terminated,
            started_at: DateTime.parse('2022-01-01 22:22:22'),
            terminated_at: DateTime.parse('2023-04-01 22:22:21'),
          )
        end

        let(:customer) { previous_subscription.customer }

        let(:subscription) do
          create(
            :subscription,
            started_at: DateTime.parse('2023-04-01 22:22:22'),
            previous_subscription:,
            customer:,
            external_id: previous_subscription.external_id,
          )
        end

        before do
          subscription

          create(
            :event,
            code: billable_metric.code,
            subscription: previous_subscription,
            customer:,
            timestamp: Time.zone.parse('2023-03-01 22:22:22'),
            properties: { value: 10 },
          )
        end

        it 'uses previous events as latest value' do
          result = aggregator.aggregate

          aggregate_failures do
            expect(result.aggregation.round(5).to_s).to eq('10.0')
            expect(result.count).to eq(0)
            expect(result.variation).to eq(0)
            expect(result.total_aggregated_units).to eq(10)
            expect(result.recurring_updated_at).to eq(from_datetime)
          end
        end
      end
    end

    context 'with events' do
      let(:events_values) do
        [
          { timestamp: DateTime.parse('2023-08-01 00:00:00.000'), value: 2 },
          { timestamp: DateTime.parse('2023-08-01 01:00:00'), value: 3 },
          { timestamp: DateTime.parse('2023-08-01 01:30:00'), value: 1 },
          { timestamp: DateTime.parse('2023-08-01 02:00:00'), value: -4 },
          { timestamp: DateTime.parse('2023-08-01 04:00:00'), value: -2 },
          { timestamp: DateTime.parse('2023-08-01 05:00:00'), value: 10 },
          { timestamp: DateTime.parse('2023-08-01 05:30:00'), value: -10 },
        ]
      end

      it 'aggregates the events' do
        result = aggregator.aggregate

        aggregate_failures do
          expect(result.aggregation.round(5).to_s).to eq('1000.02218')
          expect(result.count).to eq(7)
          expect(result.variation).to eq(0)
          expect(result.total_aggregated_units).to eq(1000)
          expect(result.recurring_updated_at).to eq('2023-08-01 05:30:00')
        end
      end
    end
  end

  context 'with group' do
    let(:group) { create(:group, billable_metric:, key: 'region', value: 'europe') }

    let(:events_values) do
      [
        { timestamp: DateTime.parse('2023-08-01 00:00:00.000'), value: 1000, region: 'europe' },
      ]
    end

    it 'aggregates the events' do
      result = aggregator.aggregate

      expect(result.aggregation.to_s).to eq('1000.0')
      expect(result.count).to eq(1)
    end
  end
end
