# frozen_string_literal: true

require 'rails_helper'

RSpec.describe BillableMetrics::Aggregations::CountService, type: :service do
  subject(:count_service) do
    described_class.new(
      event_store_class:,
      charge:,
      subscription:,
      boundaries: {
        from_datetime:,
        to_datetime:,
      },
      filters: {
        group:,
        event: pay_in_advance_event,
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
      aggregation_type: 'count_agg',
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

  let(:pay_in_advance_event) { nil }

  before do
    create_list(
      :event,
      4,
      code: billable_metric.code,
      subscription:,
      customer:,
      timestamp: Time.zone.now - 1.day,
    )
  end

  it 'aggregates the events' do
    result = count_service.aggregate

    expect(result.aggregation).to eq(4)
  end

  context 'when events are out of bounds' do
    let(:to_datetime) { Time.zone.now - 2.days }

    it 'does not take events into account' do
      result = count_service.aggregate

      expect(result.aggregation).to eq(0)
    end
  end

  context 'when group_id is given' do
    let(:parent_group) do
      create(:group, billable_metric_id: billable_metric.id, key: 'cloud', value: 'AWS')
    end

    let(:group) do
      create(
        :group,
        billable_metric_id: billable_metric.id,
        key: 'region',
        value: 'europe',
        parent_group_id: parent_group.id,
      )
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
          cloud: 'AWS',
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
          cloud: 'AWS',
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
          cloud: 'AWS',
          region: 'africa',
        },
      )
    end

    it 'aggregates the events' do
      result = count_service.aggregate

      expect(result.aggregation).to eq(2)
    end
  end

  context 'when pay_in_advance aggregation' do
    let(:pay_in_advance_event) { create(:event, subscription_id: subscription.id, customer_id: customer.id) }

    it 'assigns an pay_in_advance aggregation' do
      result = count_service.aggregate

      expect(result.pay_in_advance_aggregation).to eq(1)
    end
  end

  describe '.per_event_aggregation' do
    it 'aggregates per events' do
      result = count_service.per_event_aggregation

      expect(result.event_aggregation).to eq([1, 1, 1, 1])
    end
  end
end
