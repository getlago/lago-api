# frozen_string_literal: true

require 'rails_helper'

RSpec.describe BillableMetrics::Aggregations::LatestService, type: :service do
  subject(:latest_service) do
    described_class.new(
      event_store_class:,
      charge:,
      subscription:,
      boundaries: {
        from_datetime:,
        to_datetime:,
      },
      filters:,
    )
  end

  let(:event_store_class) { Events::Stores::PostgresStore }
  let(:filters) { { group:, grouped_by: } }

  let(:subscription) { create(:subscription) }
  let(:organization) { subscription.organization }
  let(:customer) { subscription.customer }
  let(:group) { nil }
  let(:grouped_by) { nil }

  let(:billable_metric) do
    create(
      :billable_metric,
      organization:,
      aggregation_type: 'latest_agg',
      field_name: 'total_count',
    )
  end

  let(:charge) do
    create(
      :standard_charge,
      billable_metric:,
    )
  end

  let(:from_datetime) { (Time.current - 1.month).beginning_of_day }
  let(:to_datetime) { Time.current.end_of_day }

  let(:events) do
    [
      create_list(
        :event,
        4,
        code: billable_metric.code,
        customer:,
        subscription:,
        timestamp: Time.current - 2.days,
        properties: {
          total_count: 18,
        },
      ),

      create(
        :event,
        code: billable_metric.code,
        customer:,
        subscription:,
        timestamp: Time.current - 1.day,
        properties: {
          total_count: 14,
        },
      ),
    ].flatten
  end

  before { events }

  it 'aggregates the events' do
    result = latest_service.aggregate

    expect(result.aggregation).to eq(14)
    expect(result.count).to eq(5)
  end

  context 'when events are out of bounds' do
    let(:to_datetime) { Time.current - 3.days }

    it 'does not take events into account' do
      result = latest_service.aggregate

      expect(result.aggregation).to eq(0)
      expect(result.count).to eq(0)
    end
  end

  context 'when properties is not found on events' do
    before do
      billable_metric.update!(field_name: 'foo_bar')
    end

    it 'counts as zero' do
      result = latest_service.aggregate

      expect(result.aggregation).to eq(0)
      expect(result.count).to eq(0)
    end
  end

  context 'when properties is a float' do
    let(:events) do
      [
        create(
          :event,
          code: billable_metric.code,
          customer:,
          subscription:,
          timestamp: Time.current,
          properties: {
            total_count: 14.2,
          },
        ),
      ]
    end

    it 'aggregates the events' do
      result = latest_service.aggregate

      expect(result.aggregation).to eq(14.2)
    end
  end

  context 'when properties is negative' do
    let(:events) do
      [
        create(
          :event,
          code: billable_metric.code,
          customer:,
          subscription:,
          timestamp: Time.current,
          properties: {
            total_count: -5,
          },
        ),
      ]
    end

    it 'returns zero' do
      result = latest_service.aggregate

      expect(result.aggregation).to eq(0)
    end
  end

  context 'when properties is missing' do
    let(:events) do
      [
        create(
          :event,
          code: billable_metric.code,
          customer:,
          subscription:,
          timestamp: Time.current,
        ),
      ]
    end

    it 'ignores the event' do
      result = latest_service.aggregate

      expect(result).to be_success
      expect(result.aggregation).to eq(0)
    end
  end

  context 'when group_id is given' do
    let(:group) do
      create(:group, billable_metric_id: billable_metric.id, key: 'region', value: 'europe')
    end

    let(:events) do
      [
        create(
          :event,
          code: billable_metric.code,
          customer:,
          subscription:,
          timestamp: Time.current - 2.seconds,
          properties: {
            total_count: 12,
            region: 'europe',
          },
        ),

        create(
          :event,
          code: billable_metric.code,
          customer:,
          subscription:,
          timestamp: Time.current - 1.second,
          properties: {
            total_count: 8,
            region: 'europe',
          },
        ),

        create(
          :event,
          code: billable_metric.code,
          customer:,
          subscription:,
          timestamp: Time.current - 1.second,
          properties: {
            total_count: 12,
            region: 'africa',
          },
        ),
      ].flatten
    end

    it 'aggregates the events' do
      result = latest_service.aggregate

      expect(result.aggregation).to eq(8)
      expect(result.count).to eq(2)
    end
  end

  describe '.grouped_by_aggregation' do
    let(:grouped_by) { ['agent_name'] }
    let(:agent_names) { %w[aragorn frodo gimli legolas] }

    let(:events) do
      agent_names.map do |agent_name|
        create(
          :event,
          code: billable_metric.code,
          customer:,
          subscription:,
          timestamp: Time.zone.now - 1.day,
          properties: {
            total_count: 12,
            agent_name:,
          },
        )
      end + [
        create(
          :event,
          code: billable_metric.code,
          customer:,
          subscription:,
          timestamp: Time.zone.now - 1.day,
          properties: {
            total_count: 12,
          },
        ),
      ]
    end

    it 'returns a grouped aggregations' do
      result = latest_service.aggregate

      expect(result.aggregations.count).to eq(5)

      result.aggregations.sort_by { |a| a.grouped_by['agent_name'] || '' }.each_with_index do |aggregation, index|
        expect(aggregation.aggregation).to eq(12)
        expect(aggregation.count).to eq(1)

        expect(aggregation.grouped_by['agent_name']).to eq(agent_names[index - 1]) if index.positive?
      end
    end
  end
end
