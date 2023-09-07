# frozen_string_literal: true

require 'rails_helper'

RSpec.describe BillableMetrics::Aggregations::WeightedSumService, type: :service do
  subject(:aggregator) do
    described_class.new(
      billable_metric:,
      subscription:,
      group:,
      boundaries: {
        from_datetime:,
        to_datetime:,
      },
    )
  end

  let(:subscription) { create(:subscription, started_at: DateTime.parse('2023-04-01 22:22:22')) }
  let(:organization) { subscription.organization }
  let(:customer) { subscription.customer }
  let(:group) { nil }

  let(:billable_metric) { create(:weighted_sum_billable_metric, organization:) }

  let(:from_datetime) { DateTime.parse('2023-08-01 00:00:00.000') }
  let(:to_datetime) { DateTime.parse('2023-08-31 23:59:59.999') }

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

  before do
    events_values.each do |values|
      properties = { value: values[:value] }
      properties[:region] = values[:region] if values[:region]

      create(
        :event,
        code: billable_metric.code,
        subscription:,
        timestamp: values[:timestamp],
        properties:,
      )
    end
  end

  it 'aggregates the events' do
    result = aggregator.aggregate

    expect(result.aggregation.round(5).to_s).to eq('0.0125')
    expect(result.count).to eq(7)
  end

  context 'with a single event' do
    let(:events_values) do
      [
        { timestamp: DateTime.parse('2023-08-01 00:00:00.000'), value: 1000 },
      ]
    end

    it 'aggregates the events' do
      result = aggregator.aggregate

      expect(result.aggregation.round(5).to_s).to eq('0.00037')
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

  context 'when billable metric is recurring' do
    let(:billable_metric) { create(:weighted_sum_billable_metric, :recurring, organization:) }

    let(:events_values) { [] }

    let(:quantified_event) do
      create(
        :quantified_event,
        billable_metric:,
        customer:,
        external_subscription_id: subscription.external_id,
        added_at: from_datetime - 1.day,
        properties: { recurring_value: 1000 },
      )
    end

    before { quantified_event }

    it 'uses the persisted recurring value as initial value' do
      result = aggregator.aggregate

      expect(result.aggregation.round(5).to_s).to eq('0.00037')
      expect(result.count).to eq(0)
      expect(result.variation).to eq(0)
      expect(result.recurring_value).to eq(1000)
      expect(result.recurring_updated_at).to eq(from_datetime)
    end

    context 'without quantified events' do
      let(:quantified_event) {}

      it 'falls back on 0' do
        result = aggregator.aggregate

        expect(result.aggregation.round(5).to_s).to eq('0.0')
        expect(result.count).to eq(0)
        expect(result.variation).to eq(0)
        expect(result.recurring_value).to eq(0)
        expect(result.recurring_updated_at).to eq(from_datetime)
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

        expect(result.aggregation.round(5).to_s).to eq('2.37399')
        expect(result.count).to eq(7)
        expect(result.variation).to eq(0)
        expect(result.recurring_value).to eq(1000)
        expect(result.recurring_updated_at).to eq('2023-08-01 05:30:00')
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

      expect(result.aggregation.round(5).to_s).to eq('0.00037')
      expect(result.count).to eq(1)
    end
  end
end
