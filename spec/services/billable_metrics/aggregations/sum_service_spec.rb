# frozen_string_literal: true

require 'rails_helper'

RSpec.describe BillableMetrics::Aggregations::SumService, type: :service do
  subject(:sum_service) do
    described_class.new(billable_metric: billable_metric, subscription: subscription)
  end

  let(:subscription) { create(:subscription) }
  let(:organization) { subscription.organization }
  let(:customer) { subscription.customer }

  let(:billable_metric) do
    create(
      :billable_metric,
      organization: organization,
      aggregation_type: 'sum_agg',
      field_name: 'total_count',
    )
  end

  let(:from_date) { Time.zone.today - 1.month }
  let(:to_date) { Time.zone.today }
  let(:options) do
    { free_units_per_events: 2, free_units_per_total_aggregation: 30 }
  end

  before do
    create(:group, billable_metric_id: billable_metric.id, key: 'region', value: 'europe')
    create(:group, billable_metric_id: billable_metric.id, key: 'region', value: 'usa')
    create(:group, billable_metric_id: billable_metric.id, key: 'country', value: 'france')

    create_list(
      :event,
      3,
      code: billable_metric.code,
      customer: customer,
      subscription: subscription,
      timestamp: Time.zone.now,
      properties: {
        total_count: 12,
        region: 'europe',
      },
    )

    create(
      :event,
      code: billable_metric.code,
      customer: customer,
      subscription: subscription,
      timestamp: Time.zone.now,
      properties: {
        total_count: 6,
        region: 'usa',
      },
    )

    create(
      :event,
      code: billable_metric.code,
      customer: customer,
      subscription: subscription,
      timestamp: Time.zone.now,
      properties: {
        total_count: 8,
        region: 'africa',
      },
    )

    create(
      :event,
      code: billable_metric.code,
      customer: customer,
      subscription: subscription,
      timestamp: Time.zone.now,
      properties: {
        total_count: 4,
        country: 'france',
      },
    )
  end

  it 'aggregates the events' do
    result = sum_service.aggregate(from_date: from_date, to_date: to_date, options: options)

    expect(result.aggregation).to eq(54)
    expect(result.aggregation_per_group).to eq(
      [
        [{ 'africa' => 8 }, { 'europe' => 36 }, { 'usa' => 6 }],
        [{ 'france' => 4 }],
      ],
    )
    expect(result.count).to eq(6)
    expect(result.options).to eq({ running_total: [12, 24] })
  end

  context 'when options are not present' do
    let(:options) { {} }

    it 'returns an empty running total array' do
      result = sum_service.aggregate(from_date: from_date, to_date: to_date, options: options)
      expect(result.options).to eq({ running_total: [] })
    end
  end

  context 'when option values are nil' do
    let(:options) do
      { free_units_per_events: nil, free_units_per_total_aggregation: nil }
    end

    it 'returns an empty running total array' do
      result = sum_service.aggregate(from_date: from_date, to_date: to_date, options: options)
      expect(result.options).to eq({ running_total: [] })
    end
  end

  context 'when free_units_per_events is nil' do
    let(:options) do
      { free_units_per_events: nil, free_units_per_total_aggregation: 30 }
    end

    it 'returns running total based on per total aggregation' do
      result = sum_service.aggregate(from_date: from_date, to_date: to_date, options: options)
      expect(result.options).to eq({ running_total: [12, 24, 36] })
    end
  end

  context 'when free_units_per_total_aggregation is nil' do
    let(:options) do
      { free_units_per_events: 2, free_units_per_total_aggregation: nil }
    end

    it 'returns running total based on per events' do
      result = sum_service.aggregate(from_date: from_date, to_date: to_date, options: options)
      expect(result.options).to eq({ running_total: [12, 24] })
    end
  end

  context 'when events are out of bounds' do
    let(:to_date) { Time.zone.now - 2.days }

    it 'does not take events into account' do
      result = sum_service.aggregate(from_date: from_date, to_date: to_date)

      expect(result.aggregation).to eq(0)
      expect(result.aggregation_per_group).to eq([[], []])
      expect(result.count).to eq(0)
      expect(result.options).to eq({ running_total: [] })
    end
  end

  context 'when properties is not found on events' do
    before do
      billable_metric.update!(field_name: 'foo_bar')
    end

    it 'counts as zero' do
      result = sum_service.aggregate(from_date: from_date, to_date: to_date)

      expect(result.aggregation).to eq(0)
      expect(result.aggregation_per_group).to eq([[], []])
      expect(result.count).to eq(0)
      expect(result.options).to eq({ running_total: [] })
    end
  end

  context 'when properties is a float' do
    before do
      create(
        :event,
        code: billable_metric.code,
        customer: customer,
        subscription: subscription,
        timestamp: Time.zone.now,
        properties: {
          total_count: 4.5,
          country: 'france',
        },
      )
    end

    it 'aggregates the events' do
      result = sum_service.aggregate(from_date: from_date, to_date: to_date)

      expect(result.aggregation).to eq(58.5)
      expect(result.aggregation_per_group).to eq(
        [
          [{ 'africa' => 8 }, { 'europe' => 36 }, { 'usa' => 6 }],
          [{ 'france' => 8.5 }],
        ],
      )
    end
  end

  context 'when properties is not a number' do
    before do
      create(
        :event,
        code: billable_metric.code,
        customer: customer,
        subscription: subscription,
        timestamp: Time.zone.now,
        properties: {
          total_count: 'foo_bar',
        },
      )
    end

    it 'returns a failed result' do
      result = sum_service.aggregate(from_date: from_date, to_date: to_date)

      aggregate_failures do
        expect(result).not_to be_success
        expect(result.error).to be_a(BaseService::ServiceFailure)
        expect(result.error.code).to eq('aggregation_failure')
        expect(result.error.error_message).to be_present
      end
    end
  end
end
