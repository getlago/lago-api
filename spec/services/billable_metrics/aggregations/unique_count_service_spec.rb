# frozen_string_literal: true

require 'rails_helper'

RSpec.describe BillableMetrics::Aggregations::UniqueCountService, type: :service, transaction: false do
  subject(:count_service) do
    described_class.new(
      event_store_class:,
      billable_metric:,
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

  let(:subscription) do
    create(
      :subscription,
      started_at:,
      subscription_at:,
      billing_time: :anniversary,
    )
  end

  let(:pay_in_advance_event) { nil }
  let(:subscription_at) { DateTime.parse('2022-06-09') }
  let(:started_at) { subscription_at }
  let(:organization) { subscription.organization }
  let(:customer) { subscription.customer }
  let(:group) { nil }

  let(:billable_metric) do
    create(
      :billable_metric,
      organization:,
      aggregation_type: 'unique_count_agg',
      field_name: 'unique_id',
      recurring: true,
    )
  end

  let(:from_datetime) { DateTime.parse('2022-07-09 00:00:00 UTC') }
  let(:to_datetime) { DateTime.parse('2022-08-08 23:59:59 UTC') }

  let(:added_at) { from_datetime - 1.month }
  let(:removed_at) { nil }
  let(:unique_count_event) do
    create(
      :event,
      code: billable_metric.code,
      customer:,
      subscription:,
      timestamp: added_at,
      quantified_event:,
    )
  end
  let(:quantified_event) do
    create(
      :quantified_event,
      customer:,
      added_at:,
      removed_at:,
      external_subscription_id: subscription.external_id,
      billable_metric:,
    )
  end

  before { unique_count_event }

  describe '#aggregate' do
    let(:result) { count_service.aggregate }

    context 'when there is persisted event and event added in period' do
      let(:new_quantified_event) do
        create(
          :quantified_event,
          customer:,
          added_at: from_datetime + 10.days,
          removed_at:,
          external_subscription_id: subscription.external_id,
          billable_metric:,
        )
      end
      let(:new_unique_count_event) do
        create(
          :event,
          code: billable_metric.code,
          customer:,
          subscription:,
          timestamp: from_datetime + 10.days,
          quantified_event: new_quantified_event,
        )
      end

      before { new_unique_count_event }

      it 'returns the correct number' do
        expect(result.aggregation).to eq(2)
      end
    end

    context 'when there is persisted event and event added in period but billable metric is not recurring' do
      let(:billable_metric) do
        create(
          :billable_metric,
          organization:,
          aggregation_type: 'unique_count_agg',
          field_name: 'unique_id',
          recurring: false,
        )
      end
      let(:new_unique_count_event) do
        create(
          :event,
          code: billable_metric.code,
          customer:,
          subscription:,
          timestamp: from_datetime + 10.days,
          quantified_event: new_quantified_event,
        )
      end
      let(:new_quantified_event) do
        create(
          :quantified_event,
          customer:,
          added_at: from_datetime + 10.days,
          removed_at:,
          external_subscription_id: subscription.external_id,
          billable_metric:,
        )
      end

      before { new_unique_count_event }

      it 'returns only the number of events ingested in the current period' do
        expect(result.aggregation).to eq(1)
      end
    end

    context 'with persisted metric on full period' do
      it 'returns the number of persisted metric' do
        expect(result.aggregation).to eq(1)
      end

      context 'when subscription was terminated in the period' do
        let(:subscription) do
          create(
            :subscription,
            started_at:,
            subscription_at:,
            billing_time: :anniversary,
            terminated_at: to_datetime,
            status: :terminated,
          )
        end
        let(:to_datetime) { DateTime.parse('2022-07-24 23:59:59') }

        it 'returns the correct number' do
          expect(result.aggregation).to eq(1)
        end
      end

      context 'when subscription was upgraded in the period' do
        let(:subscription) do
          create(
            :subscription,
            started_at:,
            subscription_at:,
            billing_time: :anniversary,
            terminated_at: to_datetime,
            status: :terminated,
          )
        end
        let(:to_datetime) { DateTime.parse('2022-07-24 23:59:59') }

        before do
          create(
            :subscription,
            previous_subscription: subscription,
            organization:,
            customer:,
            started_at: to_datetime,
          )
        end

        it 'returns the correct number' do
          expect(result.aggregation).to eq(1)
        end
      end

      context 'when subscription was started in the period' do
        let(:started_at) { DateTime.parse('2022-08-01') }
        let(:from_datetime) { started_at }

        it 'returns the correct number' do
          expect(result.aggregation).to eq(1)
        end
      end

      context 'when plan is pay in advance' do
        before do
          subscription.plan.update!(pay_in_advance: true)
        end

        it 'returns the correct number' do
          expect(result.aggregation).to eq(1)
        end
      end
    end

    context 'with persisted metrics added in the period' do
      let(:added_at) { from_datetime + 15.days }

      it 'returns the correct number' do
        expect(result.aggregation).to eq(1)
      end

      context 'when added on the first day of the period' do
        let(:added_at) { from_datetime }

        it 'returns the correct number' do
          expect(result.aggregation).to eq(1)
        end
      end
    end

    context 'with persisted metrics terminated in the period' do
      let(:removed_at) { to_datetime - 15.days }

      it 'returns the correct number' do
        expect(result.aggregation).to eq(0)
      end

      context 'when removed on the last day of the period' do
        let(:removed_at) { to_datetime }

        it 'returns the correct number' do
          expect(result.aggregation).to eq(0)
        end
      end
    end

    context 'with persisted metrics added and terminated in the period' do
      let(:added_at) { from_datetime + 1.day }
      let(:removed_at) { to_datetime - 1.day }

      it 'returns the correct number' do
        expect(result.aggregation).to eq(0)
      end

      context 'when added and removed the same day' do
        let(:added_at) { from_datetime + 1.day }
        let(:removed_at) { added_at.end_of_day }

        it 'returns a correct number' do
          expect(result.aggregation).to eq(0)
        end
      end
    end

    context 'when current usage context and charge is pay in advance' do
      let(:options) do
        { is_pay_in_advance: true, is_current_usage: true }
      end
      let(:previous_event) do
        create(
          :event,
          code: billable_metric.code,
          customer:,
          subscription:,
          timestamp: from_datetime + 5.days,
          quantified_event: previous_quantified_event,
          properties: {
            unique_id: '000',
          },
          metadata: {
            current_aggregation: '1',
            max_aggregation: '3',
          },
        )
      end
      let(:previous_quantified_event) do
        create(
          :quantified_event,
          customer:,
          added_at: from_datetime + 5.days,
          removed_at:,
          external_id: '000',
          external_subscription_id: subscription.external_id,
          billable_metric:,
        )
      end

      before { previous_event }

      it 'returns period maximum as aggregation' do
        result = count_service.aggregate(options:)

        expect(result.aggregation).to eq(4)
      end

      context 'when previous event does not exist' do
        let(:previous_quantified_event) { nil }

        before { billable_metric.update!(recurring: false) }

        it 'returns zero as aggregation' do
          result = count_service.aggregate(options:)

          expect(result.aggregation).to eq(0)
        end
      end
    end

    context 'when event is given' do
      let(:properties) { { unique_id: '111' } }
      let(:pay_in_advance_event) do
        create(
          :event,
          code: billable_metric.code,
          customer:,
          subscription:,
          timestamp: from_datetime + 10.days,
          properties:,
          quantified_event: new_quantified_event,
        )
      end
      let(:new_quantified_event) do
        create(
          :quantified_event,
          customer:,
          added_at: from_datetime + 10.days,
          removed_at:,
          external_subscription_id: subscription.external_id,
          billable_metric:,
        )
      end

      before { pay_in_advance_event }

      it 'assigns an pay_in_advance aggregation' do
        result = count_service.aggregate

        expect(result.pay_in_advance_aggregation).to eq(1)
      end

      context 'when dimensions are used' do
        let(:properties) { { unique_id: '111', region: 'europe' } }

        let(:group) do
          create(:group, billable_metric_id: billable_metric.id, key: 'region', value: 'europe')
        end

        it 'assigns an pay_in_advance aggregation' do
          result = count_service.aggregate

          expect(result.pay_in_advance_aggregation).to eq(1)
        end
      end

      context 'when event is missing properties' do
        let(:properties) { {} }

        it 'assigns 0 as pay_in_advance aggregation' do
          result = count_service.aggregate

          expect(result.pay_in_advance_aggregation).to be_zero
        end
      end

      context 'when current period aggregation is greater than period maximum' do
        let(:previous_event) do
          create(
            :event,
            code: billable_metric.code,
            customer:,
            subscription:,
            timestamp: from_datetime + 5.days,
            quantified_event: previous_quantified_event,
            properties: {
              unique_id: '000',
            },
            metadata: {
              current_aggregation: '7',
              max_aggregation: '7',
            },
          )
        end
        let(:previous_quantified_event) do
          create(
            :quantified_event,
            customer:,
            added_at: from_datetime + 5.days,
            removed_at:,
            external_id: '000',
            external_subscription_id: subscription.external_id,
            billable_metric:,
          )
        end

        before { previous_event }

        it 'assigns a pay_in_advance aggregation' do
          result = count_service.aggregate

          expect(result.pay_in_advance_aggregation).to eq(1)
        end
      end

      context 'when current period aggregation is less than period maximum' do
        let(:previous_event) do
          create(
            :event,
            code: billable_metric.code,
            customer:,
            subscription:,
            timestamp: from_datetime + 5.days,
            quantified_event: previous_quantified_event,
            properties: {
              unique_id: '000',
            },
            metadata: {
              current_aggregation: '4',
              max_aggregation: '7',
            },
          )
        end
        let(:previous_quantified_event) do
          create(
            :quantified_event,
            customer:,
            added_at: from_datetime + 5.days,
            removed_at:,
            external_id: '000',
            external_subscription_id: subscription.external_id,
            billable_metric:,
          )
        end

        before { previous_event }

        it 'assigns a pay_in_advance aggregation' do
          result = count_service.aggregate

          expect(result.pay_in_advance_aggregation).to eq(0)
        end
      end
    end
  end

  describe '.per_event_aggregation' do
    let(:added_at) { from_datetime }

    it 'aggregates per events added in the period' do
      result = count_service.per_event_aggregation

      expect(result.event_aggregation).to eq([1])
    end
  end
end
