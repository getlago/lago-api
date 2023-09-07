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
      create(
        :event,
        code: billable_metric.code,
        subscription:,
        timestamp: values[:timestamp],
        properties: { value: values[:value] },
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
end
