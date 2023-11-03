# frozen_string_literal: true

require 'rails_helper'

RSpec.describe BillableMetrics::Aggregations::LatestService, type: :service do
  subject(:latest_service) do
    described_class.new(
      event_store_class:,
      billable_metric:,
      subscription:,
      group:,
      boundaries: {
        from_datetime:,
        to_datetime:,
      },
    )
  end

  let(:event_store_class) { Events::Stores::PostgresStore }

  let(:subscription) { create(:subscription) }
  let(:organization) { subscription.organization }
  let(:customer) { subscription.customer }
  let(:group) { nil }

  let(:billable_metric) do
    create(
      :billable_metric,
      organization:,
      aggregation_type: 'latest_agg',
      field_name: 'total_count',
    )
  end

  let(:from_datetime) { (Time.current - 1.month).beginning_of_day }
  let(:to_datetime) { Time.current.end_of_day }

  before do
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
    )

    create(
      :event,
      code: billable_metric.code,
      customer:,
      subscription:,
      timestamp: Time.current - 1.day,
      properties: {
        total_count: 14,
      },
    )
  end

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
    before do
      create(
        :event,
        code: billable_metric.code,
        customer:,
        subscription:,
        timestamp: Time.current,
        properties: {
          total_count: 14.2,
        },
      )
    end

    it 'aggregates the events' do
      result = latest_service.aggregate

      expect(result.aggregation).to eq(14.2)
    end
  end

  context 'when properties is negative' do
    before do
      create(
        :event,
        code: billable_metric.code,
        customer:,
        subscription:,
        timestamp: Time.current,
        properties: {
          total_count: -5,
        },
      )
    end

    it 'returns zero' do
      result = latest_service.aggregate

      expect(result.aggregation).to eq(0)
    end
  end

  context 'when properties is missing' do
    before do
      create(
        :event,
        code: billable_metric.code,
        customer:,
        subscription:,
        timestamp: Time.current,
      )
    end

    it 'ignores the event' do
      result = latest_service.aggregate

      expect(result).to be_success
      expect(result.aggregation).to eq(14)
    end
  end

  context 'when group_id is given' do
    let(:group) do
      create(:group, billable_metric_id: billable_metric.id, key: 'region', value: 'europe')
    end

    before do
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
      )

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
      )

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
      )
    end

    it 'aggregates the events' do
      result = latest_service.aggregate

      expect(result.aggregation).to eq(8)
      expect(result.count).to eq(2)
    end
  end
end
