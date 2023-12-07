# frozen_string_literal: true

require 'rails_helper'

RSpec.describe BillableMetrics::ProratedAggregations::SumService, type: :service, transaction: false do
  subject(:sum_service) do
    described_class.new(
      event_store_class:,
      charge:,
      subscription:,
      group:,
      event: pay_in_advance_event,
      boundaries: {
        from_datetime:,
        to_datetime:,
      },
    )
  end

  let(:event_store_class) { Events::Stores::PostgresStore }

  let(:subscription) { create(:subscription, started_at: Time.zone.parse('2022-12-01 00:00:00')) }
  let(:organization) { subscription.organization }
  let(:customer) { subscription.customer }
  let(:group) { nil }

  let(:billable_metric) do
    create(
      :billable_metric,
      organization:,
      aggregation_type: 'sum_agg',
      field_name: 'total_count',
      recurring: true,
    )
  end

  let(:charge) do
    create(
      :standard_charge,
      billable_metric:,
    )
  end

  let(:from_datetime) { Time.zone.parse('2023-05-01 00:00:00') }
  let(:to_datetime) { Time.zone.parse('2023-05-31 23:59:59') }
  let(:pay_in_advance_event) { nil }
  let(:options) { {} }

  let(:old_events) do
    create_list(
      :event,
      2,
      code: billable_metric.code,
      customer:,
      subscription:,
      timestamp: subscription.started_at + 3.months,
      properties: {
        total_count: 2.5,
      },
    )
  end
  let(:latest_events) do
    create_list(
      :event,
      2,
      code: billable_metric.code,
      customer:,
      subscription:,
      timestamp: from_datetime + 25.days,
      properties: {
        total_count: 12,
      },
    )
  end

  before do
    old_events
    latest_events
  end

  it 'aggregates the events' do
    result = sum_service.aggregate(options:)

    expect(result.aggregation).to eq(9.64517) # 5 + (12*6/31) + (12*6/31)
    expect(result.pay_in_advance_aggregation).to be_zero
    expect(result.count).to eq(4)
  end

  context 'when aggregation is performed on billing date for pay in advance case' do
    let(:options) do
      { is_pay_in_advance: true, is_current_usage: false }
    end

    it 'aggregates the events without proration' do
      result = sum_service.aggregate(options:)

      expect(result.aggregation).to eq(29)
      expect(result.pay_in_advance_aggregation).to be_zero
      expect(result.count).to eq(4)
    end
  end

  context 'when events are out of bounds' do
    let(:latest_events) do
      create_list(
        :event,
        4,
        code: billable_metric.code,
        customer:,
        subscription:,
        timestamp: to_datetime + 1.day,
        properties: {
          total_count: 12,
        },
      )
    end

    it 'does not take events into account' do
      result = sum_service.aggregate

      expect(result.aggregation).to eq(5)
      expect(result.count).to eq(2)
    end
  end

  context 'when properties is not found on events' do
    before do
      billable_metric.update!(field_name: 'foo_bar')
    end

    it 'counts as zero' do
      result = sum_service.aggregate

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
        timestamp: from_datetime + 30.days,
        properties: {
          total_count: 4.5,
        },
      )
    end

    it 'aggregates the events' do
      result = sum_service.aggregate

      expect(result.aggregation).to eq(9.64517 + 0.14516)
    end
  end

  context 'when properties is not a number' do
    before do
      create(
        :event,
        code: billable_metric.code,
        customer:,
        subscription:,
        timestamp: from_datetime + 30.days,
        properties: {
          total_count: 'foo_bar',
        },
      )
    end

    it 'ignores the event' do
      result = sum_service.aggregate

      aggregate_failures do
        expect(result).to be_success
        expect(result.aggregation).to eq(9.64517) # 5 + (12*6/31) + (12*6/31)
        expect(result.count).to eq(4)
      end
    end
  end

  context 'when current usage context and charge is pay in arrear' do
    let(:options) do
      { is_pay_in_advance: false, is_current_usage: true }
    end

    it 'returns period maximum as aggregation' do
      result = sum_service.aggregate(options:)

      expect(result.aggregation).to eq(9.64517)
      expect(result.current_usage_units).to eq(29)
    end
  end

  context 'when current usage context and charge is pay in advance' do
    let(:options) do
      { is_pay_in_advance: true, is_current_usage: true }
    end

    let(:latest_events) do
      create(
        :event,
        code: billable_metric.code,
        customer:,
        subscription:,
        timestamp: to_datetime - 3.days,
        properties: {
          total_count: 4,
        },
      )
    end

    let(:cached_aggregation) do
      create(
        :cached_aggregation,
        organization: billable_metric.organization,
        charge:,
        external_subscription_id: subscription.external_id,
        event_id: latest_events.id,
        timestamp: latest_events.timestamp,
        current_aggregation: '4',
        max_aggregation: '6',
        max_aggregation_with_proration: '3.8',
      )
    end

    before { cached_aggregation }

    it 'returns period maximum as aggregation' do
      result = sum_service.aggregate(options:)

      expect(result.aggregation).to eq(8.8)
      expect(result.current_usage_units).to eq(9)
    end

    context 'when cached aggregation does not exist' do
      let(:latest_events) { nil }
      let(:cached_aggregation) { nil }

      it 'returns zero as aggregation' do
        result = sum_service.aggregate(options:)

        expect(result.aggregation).to eq(5)
        expect(result.current_usage_units).to eq(5)
      end
    end
  end

  context 'when current usage context and charge is pay in advance and just upgraded' do
    let(:from_datetime) { Time.zone.parse('2023-05-15 00:00:00') }
    let(:options) do
      { is_pay_in_advance: true, is_current_usage: true }
    end
    let(:latest_events) { nil }

    it 'returns correct values' do
      result = sum_service.aggregate(options:)

      expect(result.aggregation).to eq((5 * 17.fdiv(31)).ceil(5))
      expect(result.current_usage_units).to eq(5)
    end
  end

  context 'when current usage context and charge is pay in advance and just upgraded and new event in period' do
    let(:from_datetime) { Time.zone.parse('2023-05-15 00:00:00') }
    let(:options) do
      { is_pay_in_advance: true, is_current_usage: true }
    end

    let(:latest_events) do
      create(
        :event,
        code: billable_metric.code,
        customer:,
        subscription:,
        timestamp: to_datetime - 10.days,
        properties: {
          total_count: 4,
        },
      )
    end

    let(:cached_aggregation) do
      create(
        :cached_aggregation,
        organization: billable_metric.organization,
        charge:,
        external_subscription_id: subscription.external_id,
        event_id: latest_events.id,
        timestamp: latest_events.timestamp,
        current_aggregation: '4',
        max_aggregation: '6',
        max_aggregation_with_proration: '3.8',
      )
    end

    before { cached_aggregation }

    it 'returns correct values' do
      result = sum_service.aggregate(options:)

      expect(result.aggregation).to eq((5 * 17.fdiv(31)).ceil(5) + 3.8)
      expect(result.current_usage_units).to eq(9)
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
        timestamp: from_datetime + 30.days,
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
        timestamp: from_datetime + 30.days,
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
        timestamp: from_datetime + 30.days,
        properties: {
          total_count: 12,
          region: 'africa',
        },
      )
    end

    it 'aggregates the events' do
      result = sum_service.aggregate(options:)

      expect(result.aggregation).to eq(0.64517) # (1/31 * 8) + (1/31 * 12)
      expect(result.count).to eq(2)
    end
  end

  context 'when subscription was upgraded in the period' do
    let(:old_subscription) do
      create(
        :subscription,
        external_id: subscription.external_id,
        organization:,
        customer:,
        started_at: from_datetime - 10.days,
        terminated_at: from_datetime,
        status: :terminated,
      )
    end

    before do
      old_subscription
      subscription.update!(previous_subscription: old_subscription)
      create(
        :event,
        code: billable_metric.code,
        customer:,
        subscription: old_subscription,
        timestamp: from_datetime - 5.days,
        properties: {
          total_count: 10,
        },
      )
    end

    it 'returns the correct number' do
      result = sum_service.aggregate(options:)

      expect(result.aggregation).to eq(19.64517) # 10 + 5 + (6/31*12) + (6/31*12)
    end
  end

  context 'when event is given' do
    let(:old_events) { nil }
    let(:latest_events) { nil }
    let(:pay_in_advance_event) do
      create(
        :event,
        code: billable_metric.code,
        customer:,
        subscription:,
        timestamp: from_datetime + 29.days,
        properties:,
      )
    end

    let(:properties) { { total_count: 10 } }

    it 'assigns a pay_in_advance aggregation' do
      result = sum_service.aggregate

      expect(result.pay_in_advance_aggregation).to eq(0.64517)
    end

    context 'when current period aggregation is greater than period maximum' do
      let(:latest_events) do
        create(
          :event,
          code: billable_metric.code,
          customer:,
          subscription:,
          timestamp: from_datetime + 28.days,
          properties: {
            total_count: -6,
          },
        )
      end

      let(:cached_aggregation) do
        create(
          :cached_aggregation,
          organization: billable_metric.organization,
          charge:,
          external_subscription_id: subscription.external_id,
          event_id: latest_events.id,
          timestamp: latest_events.timestamp,
          current_aggregation: '4',
          max_aggregation: '10',
          max_aggregation_with_proration: '3.2',
        )
      end

      before { cached_aggregation }

      it 'assigns a pay_in_advance aggregation' do
        result = sum_service.aggregate

        expect(result.pay_in_advance_aggregation).to eq(0.25807) # 4 * (2/31)
      end
    end

    context 'when current period aggregation is less than period maximum' do
      let(:properties) { { total_count: -2 } }
      let(:latest_events) do
        create(
          :event,
          code: billable_metric.code,
          customer:,
          subscription:,
          timestamp: from_datetime + 28.days,
          properties: {
            total_count: -6,
          },
        )
      end

      let(:cached_aggregation) do
        create(
          :cached_aggregation,
          organization: billable_metric.organization,
          charge:,
          external_subscription_id: subscription.external_id,
          event_id: latest_events.id,
          timestamp: latest_events.timestamp,
          current_aggregation: '4',
          max_aggregation: '10',
          max_aggregation_with_proration: '3.2',
        )
      end

      before { cached_aggregation }

      it 'assigns a pay_in_advance aggregation' do
        result = sum_service.aggregate

        expect(result.pay_in_advance_aggregation).to eq(0)
        expect(result.units_applied).to eq('-2')
      end
    end

    context 'when properties is a float' do
      let(:properties) { { total_count: 12.4 } }

      it 'assigns a pay_in_advance aggregation' do
        result = sum_service.aggregate

        expect(result.pay_in_advance_aggregation).to eq(0.8) # 2/31*12.4
      end
    end

    context 'when event property does not match metric field name' do
      let(:properties) { { final_count: 10 } }

      it 'assigns 0 as pay_in_advance aggregation' do
        result = sum_service.aggregate

        expect(result.pay_in_advance_aggregation).to be_zero
      end
    end

    context 'when event is missing properties' do
      let(:properties) { {} }

      it 'assigns 0 as pay_in_advance aggregation' do
        result = sum_service.aggregate

        expect(result.pay_in_advance_aggregation).to be_zero
      end
    end
  end

  describe '.per_event_aggregation' do
    it 'aggregates per events' do
      sum_service.options = {}
      result = sum_service.per_event_aggregation

      expect(result.event_aggregation).to eq([5, 12, 12])
      expect(result.event_prorated_aggregation.map { |el| el.round(5) }).to eq([5, 2.32258, 2.32258])
    end
  end
end
