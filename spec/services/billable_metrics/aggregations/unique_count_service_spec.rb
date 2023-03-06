# frozen_string_literal: true

require 'rails_helper'

RSpec.describe BillableMetrics::Aggregations::UniqueCountService, type: :service do
  subject(:count_service) do
    described_class.new(
      billable_metric:,
      subscription:,
      group:,
      event: instant_event,
    )
  end

  let(:subscription) { create(:subscription) }
  let(:organization) { subscription.organization }
  let(:customer) { subscription.customer }
  let(:group) { nil }

  let(:billable_metric) do
    create(
      :billable_metric,
      organization:,
      aggregation_type: 'unique_count_agg',
      field_name: 'anonymous_id',
    )
  end

  let(:from_datetime) { (Time.current - 1.month).beginning_of_day }
  let(:to_datetime) { Time.current.end_of_day }

  let(:instant_event) { nil }

  before do
    create_list(
      :event,
      4,
      code: billable_metric.code,
      customer:,
      subscription:,
      timestamp: Time.zone.now - 1.day,
      properties: {
        anonymous_id: 'foo_bar',
      },
    )
  end

  it 'aggregates the events' do
    result = count_service.aggregate(from_datetime:, to_datetime:)

    expect(result.aggregation).to eq(1)
    expect(result.count).to eq(4)
  end

  context 'when events are out of bounds' do
    let(:to_datetime) { Time.zone.now - 2.days }

    it 'does not take events into account' do
      result = count_service.aggregate(from_datetime:, to_datetime:)

      expect(result.aggregation).to eq(0)
      expect(result.count).to eq(0)
    end
  end

  context 'when properties is not found on events' do
    before do
      billable_metric.update!(field_name: 'foo_bar')
    end

    it 'counts as zero' do
      result = count_service.aggregate(from_datetime:, to_datetime:)

      expect(result.aggregation).to eq(0)
      expect(result.count).to eq(0)
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
        timestamp: Time.zone.now,
        properties: {
          anonymous_id: 'foo_bar',
          region: 'europe',
        },
      )

      create(
        :event,
        code: billable_metric.code,
        customer:,
        subscription:,
        timestamp: Time.zone.now,
        properties: {
          anonymous_id: 'foo_bar',
          region: 'europe',
        },
      )

      create(
        :event,
        code: billable_metric.code,
        customer:,
        subscription:,
        timestamp: Time.zone.now,
        properties: {
          anonymous_id: 'foo_bar',
          region: 'africa',
        },
      )
    end

    it 'aggregates the events' do
      result = count_service.aggregate(from_datetime:, to_datetime:)

      expect(result.aggregation).to eq(1)
      expect(result.count).to eq(2)
    end
  end

  context 'when event is given' do
    let(:instant_event) do
      create(
        :event,
        code: billable_metric.code,
        customer:,
        subscription:,
        timestamp: Time.zone.now - 1.day,
        properties:,
      )
    end

    let(:properties) { { anonymous_id: 'unknown' } }

    it 'assigns an instant aggregation' do
      result = count_service.aggregate(from_datetime:, to_datetime:)

      expect(result.instant_aggregation).to eq(1)
    end

    context 'when event propety is already known' do
      before do
        create(
          :event,
          code: billable_metric.code,
          customer:,
          subscription:,
          timestamp: Time.zone.now - 1.day,
          properties:,
        )
      end

      it 'assigns zero as instant aggregation' do
        result = count_service.aggregate(from_datetime:, to_datetime:)

        expect(result.instant_aggregation).to be_zero
      end
    end

    context 'when event is missing properties' do
      let(:properties) { {} }

      it 'assigns 0 as instant aggregation' do
        result = count_service.aggregate(from_datetime:, to_datetime:)

        expect(result.instant_aggregation).to be_zero
      end
    end
  end
end
