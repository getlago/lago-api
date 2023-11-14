# frozen_string_literal: true

require 'rails_helper'

RSpec.describe BillableMetrics::Aggregations::MaxService, type: :service do
  subject(:max_service) do
    described_class.new(
      event_store_class:,
      charge:,
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
      aggregation_type: 'max_agg',
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

  before do
    create_list(
      :event,
      4,
      code: billable_metric.code,
      customer:,
      subscription:,
      timestamp: Time.zone.now - 2.days,
      properties: {
        total_count: rand(10),
      },
    )

    create(
      :event,
      code: billable_metric.code,
      customer:,
      subscription:,
      timestamp: Time.zone.now - 1.day,
      properties: {
        total_count: 12,
      },
    )
  end

  it 'aggregates the events' do
    result = max_service.aggregate

    expect(result.aggregation).to eq(12)
    expect(result.count).to eq(5)
  end

  context 'when events are out of bounds' do
    let(:to_datetime) { Time.zone.now - 3.days }

    it 'does not take events into account' do
      result = max_service.aggregate

      expect(result.aggregation).to eq(0)
      expect(result.count).to eq(0)
    end
  end

  context 'when properties is not found on events' do
    before do
      billable_metric.update!(field_name: 'foo_bar')
    end

    it 'counts as zero' do
      result = max_service.aggregate

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
        timestamp: Time.zone.now - 1.day,
        properties: {
          total_count: 14.2,
        },
      )
    end

    it 'aggregates the events' do
      result = max_service.aggregate

      expect(result.aggregation).to eq(14.2)
    end
  end

  context 'when properties is not a number' do
    before do
      create(
        :event,
        code: billable_metric.code,
        customer:,
        subscription:,
        timestamp: Time.zone.now - 1.day,
        properties: {
          total_count: 'foo_bar',
        },
      )
    end

    it 'ignores the event' do
      result = max_service.aggregate

      aggregate_failures do
        expect(result).to be_success
        expect(result.aggregation).to eq(12)
        expect(result.count).to eq(5)
      end
    end
  end

  context 'when properties is missing' do
    before do
      create(
        :event,
        code: billable_metric.code,
        customer:,
        subscription:,
        timestamp: Time.zone.now - 1.day,
      )
    end

    it 'ignore the event' do
      result = max_service.aggregate

      expect(result).to be_success
      expect(result.aggregation).to eq(12)
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
        timestamp: Time.zone.now - 1.day,
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
        timestamp: Time.zone.now - 1.day,
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
        timestamp: Time.zone.now - 1.day,
        properties: {
          total_count: 12,
          region: 'africa',
        },
      )
    end

    it 'aggregates the events' do
      result = max_service.aggregate

      expect(result.aggregation).to eq(12)
      expect(result.count).to eq(2)
    end
  end

  describe '.per_event_aggregation' do
    it 'aggregates per events' do
      result = max_service.per_event_aggregation

      expect(result.event_aggregation).to eq([0, 0, 0, 0, 12])
    end
  end
end
