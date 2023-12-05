# frozen_string_literal: true

require 'rails_helper'

RSpec.describe BillableMetrics::ProratedAggregations::UniqueCountService, type: :service, transaction: false do
  subject(:unique_count_service) do
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

  let(:subscription) do
    create(
      :subscription,
      started_at:,
      subscription_at:,
      billing_time: :anniversary,
    )
  end

  let(:pay_in_advance_event) { nil }
  let(:options) { {} }
  let(:subscription_at) { Time.zone.parse('2022-06-09') }
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

  let(:charge) do
    create(
      :standard_charge,
      billable_metric:,
    )
  end

  let(:from_datetime) { Time.zone.parse('2022-07-09 00:00:00 UTC') }
  let(:to_datetime) { Time.zone.parse('2022-08-08 23:59:59 UTC') }

  let(:added_at) { from_datetime - 1.month }
  let(:removed_at) { nil }
  let(:quantified_event) do
    create(
      :quantified_event,
      added_at:,
      removed_at:,
      external_subscription_id: subscription.external_id,
      billable_metric:,
    )
  end

  before { quantified_event }

  describe '#aggregate' do
    let(:result) { unique_count_service.aggregate(options:) }

    context 'with persisted metric on full period' do
      it 'returns the number of persisted metric' do
        expect(result.aggregation).to eq(1)
      end

      context 'when there is persisted event and event added in period' do
        let(:new_quantified_event) do
          create(
            :quantified_event,
            added_at: from_datetime + 10.days,
            removed_at:,
            external_subscription_id: subscription.external_id,
            billable_metric:,
          )
        end

        before { new_quantified_event }

        it 'returns the correct number' do
          expect(result.aggregation).to eq((1 + 21.fdiv(31)).ceil(5))
        end
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
        let(:to_datetime) { Time.zone.parse('2022-07-24 23:59:59') }

        it 'returns the prorata of the full duration' do
          expect(result.aggregation).to eq(16.fdiv(31).ceil(5))
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
        let(:to_datetime) { Time.zone.parse('2022-07-24 23:59:59') }

        before do
          create(
            :subscription,
            previous_subscription: subscription,
            organization:,
            customer:,
            started_at: to_datetime,
          )
        end

        it 'returns the prorata of the full duration' do
          expect(result.aggregation).to eq(16.fdiv(31).ceil(5))
        end
      end

      context 'when subscription was started in the period' do
        let(:started_at) { Time.zone.parse('2022-08-01') }
        let(:from_datetime) { started_at }

        it 'returns the prorata of the full duration' do
          expect(result.aggregation).to eq(8.fdiv(31).ceil(5))
        end
      end

      context 'when dimensions are used' do
        let(:quantified_event) do
          create(
            :quantified_event,
            added_at:,
            removed_at:,
            external_subscription_id: subscription.external_id,
            billable_metric:,
            properties: { unique_id: '111', region: 'europe' },
          )
        end

        let(:group) do
          create(:group, billable_metric_id: billable_metric.id, key: 'region', value: 'europe')
        end

        it 'returns the number of persisted metric' do
          expect(result.aggregation).to eq(1)
        end
      end

      context 'when plan is pay in advance' do
        before do
          subscription.plan.update!(pay_in_advance: true)
        end

        it 'returns the number of persisted metric' do
          expect(result.aggregation).to eq(1)
        end
      end
    end

    context 'with persisted metrics added in the period' do
      let(:added_at) { from_datetime + 15.days }

      it 'returns the prorata of the full duration' do
        expect(result.aggregation).to eq(16.fdiv(31).ceil(5))
      end

      context 'when added on the first day of the period' do
        let(:added_at) { from_datetime }

        it 'returns the full duration' do
          expect(result.aggregation).to eq(1)
        end
      end
    end

    context 'with persisted metrics terminated in the period' do
      let(:removed_at) { to_datetime - 15.days }

      it 'returns the prorata of the full duration' do
        expect(result.aggregation).to eq(16.fdiv(31).ceil(5))
      end

      context 'when removed on the last day of the period' do
        let(:removed_at) { to_datetime }

        it 'returns the full duration' do
          expect(result.aggregation).to eq(1)
        end
      end
    end

    context 'with persisted metrics added and terminated in the period' do
      let(:added_at) { from_datetime + 1.day }
      let(:removed_at) { to_datetime - 1.day }

      it 'returns the prorata of the full duration' do
        expect(result.aggregation).to eq(29.fdiv(31).ceil(5))
      end

      context 'when added and removed the same day' do
        let(:added_at) { from_datetime + 1.day }
        let(:removed_at) { added_at.end_of_day }

        it 'returns a 1 day duration' do
          expect(result.aggregation).to eq(1.fdiv(31).ceil(5))
        end
      end
    end

    context 'when current usage context and charge is pay in arrear' do
      let(:options) do
        { is_pay_in_advance: false, is_current_usage: true }
      end
      let(:new_quantified_event) do
        create(
          :quantified_event,
          added_at: from_datetime + 10.days,
          removed_at:,
          external_subscription_id: subscription.external_id,
          billable_metric:,
        )
      end

      before { new_quantified_event }

      it 'returns correct result' do
        expect(result.aggregation).to eq((1 + 21.fdiv(31)).ceil(5))
        expect(result.current_usage_units).to eq(2)
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
          external_customer_id: customer.external_id,
          external_subscription_id: subscription.external_id,
          timestamp: from_datetime + 5.days,
          quantified_event: previous_quantified_event,
          properties: {
            unique_id: '000',
          },
        )
      end

      let(:previous_quantified_event) do
        create(
          :quantified_event,
          organization:,
          added_at: from_datetime + 5.days,
          removed_at:,
          external_id: '000',
          external_subscription_id: subscription.external_id,
          billable_metric:,
        )
      end

      let(:cached_aggregation) do
        create(
          :cached_aggregation,
          organization:,
          charge:,
          event_id: previous_event.id,
          external_subscription_id: subscription.external_id,
          timestamp: from_datetime + 5.days,
          current_aggregation: '1',
          max_aggregation: '1',
          max_aggregation_with_proration: '0.8',
        )
      end

      before { cached_aggregation }

      it 'returns period maximum as aggregation' do
        expect(result.aggregation).to eq(1.8)
        expect(result.current_usage_units).to eq(2)
      end

      context 'when cached aggregation does not exist' do
        let(:cached_aggregation) { nil }

        it 'returns only the past aggregation' do
          expect(result.aggregation).to eq(1)
          expect(result.current_usage_units).to eq(1)
        end
      end
    end

    context 'when event is given' do
      let(:properties) { { unique_id: '111' } }
      let(:pay_in_advance_event) do
        create(
          :event,
          code: billable_metric.code,
          external_customer_id: customer.external_id,
          external_subscription_id: subscription.external_id,
          timestamp: from_datetime + 10.days,
          properties:,
          quantified_event: new_quantified_event,
        )
      end

      let(:new_quantified_event) do
        create(
          :quantified_event,
          organization:,
          added_at: from_datetime + 10.days,
          removed_at:,
          external_subscription_id: subscription.external_id,
          billable_metric:,
        )
      end

      before { pay_in_advance_event }

      it 'assigns an pay_in_advance aggregation' do
        expect(result.pay_in_advance_aggregation).to eq(21.fdiv(31).ceil(5))
      end

      context 'when event is missing properties' do
        let(:properties) { {} }

        it 'assigns 0 as pay_in_advance aggregation' do
          expect(result.pay_in_advance_aggregation).to be_zero
        end
      end

      context 'when current period aggregation is greater than period maximum' do
        let(:previous_event) do
          create(
            :event,
            code: billable_metric.code,
            external_customer_id: customer.external_id,
            external_subscription_id: subscription.external_id,
            timestamp: from_datetime + 5.days,
            quantified_event: previous_quantified_event,
            properties: {
              unique_id: '000',
            },
            metadata: {
              current_aggregation: '7',
              max_aggregation: '7',
              max_aggregation_with_proration: '5.8',
            },
          )
        end
        let(:previous_quantified_event) do
          create(
            :quantified_event,
            added_at: from_datetime + 5.days,
            removed_at:,
            external_id: '000',
            external_subscription_id: subscription.external_id,
            billable_metric:,
          )
        end

        before { previous_event }

        it 'assigns a pay_in_advance aggregation' do
          expect(result.pay_in_advance_aggregation).to eq(21.fdiv(31).ceil(5))
        end
      end

      context 'when current period aggregation is less than period maximum' do
        let(:previous_event) do
          create(
            :event,
            code: billable_metric.code,
            external_customer_id: customer.external_id,
            external_subscription_id: subscription.external_id,
            timestamp: from_datetime + 5.days,
            quantified_event: previous_quantified_event,
            properties: {
              unique_id: '000',
            },
          )
        end

        let(:previous_quantified_event) do
          create(
            :quantified_event,
            added_at: from_datetime + 5.days,
            removed_at:,
            external_id: '000',
            external_subscription_id: subscription.external_id,
            billable_metric:,
          )
        end

        let(:cached_aggregation) do
          create(
            :cached_aggregation,
            organization:,
            charge:,
            event_id: previous_event.id,
            external_subscription_id: subscription.external_id,
            timestamp: previous_event.timestamp,
            current_aggregation: '4',
            max_aggregation: '7',
            max_aggregation_with_proration: '5.8',
          )
        end

        before { cached_aggregation }

        it 'assigns a pay_in_advance aggregation' do
          expect(result.pay_in_advance_aggregation).to eq(0)
          expect(result.units_applied).to eq(1)
        end
      end
    end
  end

  describe '.per_event_aggregation' do
    before { unique_count_service.options = {} }

    context 'with event added in the period' do
      let(:added_at) { from_datetime + 10.days }

      it 'aggregates per events' do
        result = unique_count_service.per_event_aggregation

        expect(result.event_aggregation).to eq([1])
        expect(result.event_prorated_aggregation.map { |el| el.ceil(5) }).to eq([21.fdiv(31).ceil(5)])
      end
    end

    context 'with persisted metrics removed in the period' do
      let(:removed_at) { to_datetime - 15.days }

      it 'aggregates per events' do
        result = unique_count_service.per_event_aggregation

        expect(result.event_aggregation).to eq([1])
        expect(result.event_prorated_aggregation.map { |el| el.ceil(5) }).to eq([16.fdiv(31).ceil(5)])
      end

      context 'when removed on the last day of the period' do
        let(:removed_at) { to_datetime }

        it 'aggregates per events' do
          result = unique_count_service.per_event_aggregation

          expect(result.event_aggregation).to eq([1])
          expect(result.event_prorated_aggregation).to eq([1])
        end
      end
    end

    context 'with persisted metrics added and removed in the period' do
      let(:added_at) { from_datetime + 1.day }
      let(:removed_at) { to_datetime - 1.day }

      it 'aggregates per events' do
        result = unique_count_service.per_event_aggregation

        expect(result.event_aggregation).to eq([1])
        expect(result.event_prorated_aggregation.map { |el| el.ceil(5) }).to eq([29.fdiv(31).ceil(5)])
      end

      context 'when added and removed the same day' do
        let(:added_at) { from_datetime + 1.day }
        let(:removed_at) { added_at }

        it 'aggregates per events' do
          result = unique_count_service.per_event_aggregation

          expect(result.event_aggregation).to eq([1])
          expect(result.event_prorated_aggregation.map { |el| el.ceil(5) }).to eq([1.fdiv(31).ceil(5)])
        end
      end
    end

    context 'with multiple events added in the period and with one added and removed during period' do
      let(:added_at) { from_datetime + 10.days }
      let(:quantified_event2) do
        create(
          :quantified_event,
          added_at: from_datetime + 10.days,
          removed_at: nil,
          external_subscription_id: subscription.external_id,
          billable_metric:,
        )
      end
      let(:quantified_event3) do
        create(
          :quantified_event,
          added_at: from_datetime + 20.days,
          removed_at: from_datetime + 20.days,
          external_subscription_id: subscription.external_id,
          billable_metric:,
        )
      end

      before do
        quantified_event2
        quantified_event3
      end

      it 'aggregates per events' do
        result = unique_count_service.per_event_aggregation

        first = 21.fdiv(31).ceil(5)
        second = 1.fdiv(31).ceil(5)

        expect(result.event_aggregation).to eq([1, 1, 1])
        expect(result.event_prorated_aggregation.map { |el| el.ceil(5) }).to eq([first, first, second])
      end
    end

    context 'with multiple events added and removed in the period and with one persisted' do
      let(:quantified_event2) do
        create(
          :quantified_event,
          added_at: from_datetime + 10.days,
          removed_at: nil,
          external_subscription_id: subscription.external_id,
          billable_metric:,
        )
      end
      let(:quantified_event3) do
        create(
          :quantified_event,
          added_at: from_datetime + 20.days,
          removed_at: from_datetime + 20.days,
          external_subscription_id: subscription.external_id,
          billable_metric:,
        )
      end

      before do
        quantified_event2
        quantified_event3
      end

      it 'aggregates per events' do
        result = unique_count_service.per_event_aggregation

        second = 21.fdiv(31).ceil(5)
        third = 1.fdiv(31).ceil(5)

        expect(result.event_aggregation).to eq([1, 1, 1])
        expect(result.event_prorated_aggregation.map { |el| el.ceil(5) }).to eq([1, second, third])
      end
    end
  end
end
