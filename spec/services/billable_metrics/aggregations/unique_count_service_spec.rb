# frozen_string_literal: true

require 'rails_helper'

RSpec.describe BillableMetrics::Aggregations::UniqueCountService, type: :service, transaction: false do
  subject(:count_service) do
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
  let(:filters) { { group:, event: pay_in_advance_event, grouped_by: } }

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
  let(:grouped_by) { nil }

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

  let(:from_datetime) { DateTime.parse('2022-07-09 00:00:00 UTC') }
  let(:to_datetime) { DateTime.parse('2022-08-08 23:59:59 UTC') }

  let(:added_at) { from_datetime - 1.month }
  let(:removed_at) { nil }
  let(:unique_count_event) do
    create(
      :event,
      organization_id: organization.id,
      code: billable_metric.code,
      external_customer_id: customer.external_id,
      external_subscription_id: subscription.external_id,
      timestamp: added_at,
      properties: { unique_id: quantified_event.external_id },
    )
  end
  let(:quantified_event) do
    create(
      :quantified_event,
      organization:,
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
          organization:,
          added_at: from_datetime + 10.days,
          removed_at:,
          external_subscription_id: subscription.external_id,
          billable_metric:,
        )
      end
      let(:new_unique_count_event) do
        create(
          :event,
          organization_id: organization.id,
          code: billable_metric.code,
          external_customer_id: customer.external_id,
          external_subscription_id: subscription.external_id,
          timestamp: from_datetime + 10.days,
          properties: { unique_id: new_quantified_event.external_id },
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
          organization_id: organization.id,
          code: billable_metric.code,
          external_customer_id: customer.external_id,
          external_subscription_id: subscription.external_id,
          timestamp: from_datetime + 10.days,
          properties: { unique_id: new_quantified_event.external_id },
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
          organization_id: organization.id,
          code: billable_metric.code,
          external_customer_id: customer.external_id,
          external_subscription_id: subscription.external_id,
          timestamp: from_datetime + 5.days,
          properties: {
            unique_id: previous_quantified_event.external_id,
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
          timestamp: previous_event.timestamp,
          current_aggregation: '1',
          max_aggregation: '3',
        )
      end

      before { cached_aggregation }

      it 'returns period maximum as aggregation' do
        result = count_service.aggregate(options:)

        expect(result.aggregation).to eq(4)
      end

      context 'when cached aggregation does not exist' do
        let(:cached_aggregation) { nil }
        let(:previous_quantified_event) { nil }

        before { billable_metric.update!(recurring: false) }

        it 'returns zero as aggregation' do
          result = count_service.aggregate(options:)

          expect(result.aggregation).to eq(0)
        end
      end
    end

    context 'when event is given' do
      let(:properties) { { unique_id: new_quantified_event.external_id } }
      let(:pay_in_advance_event) do
        create(
          :event,
          organization_id: organization.id,
          code: billable_metric.code,
          external_customer_id: customer.external_id,
          external_subscription_id: subscription.external_id,
          timestamp: from_datetime + 10.days,
          properties:,
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
            organization_id: organization.id,
            code: billable_metric.code,
            external_customer_id: customer.external_id,
            external_subscription_id: subscription.external_id,
            timestamp: from_datetime + 5.days,
            properties: {
              unique_id: previous_quantified_event.external_id,
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
            timestamp: previous_event.timestamp,
            current_aggregation: '7',
            max_aggregation: '7',
          )
        end

        before { cached_aggregation }

        it 'assigns a pay_in_advance aggregation' do
          result = count_service.aggregate

          expect(result.pay_in_advance_aggregation).to eq(1)
        end
      end

      context 'when current period aggregation is less than period maximum' do
        let(:previous_event) do
          create(
            :event,
            organization_id: organization.id,
            code: billable_metric.code,
            external_customer_id: customer.external_id,
            external_subscription_id: subscription.external_id,
            timestamp: from_datetime + 5.days,
            properties: {
              unique_id: previous_quantified_event.external_id,
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
            timestamp: previous_event.timestamp,
            current_aggregation: '4',
            max_aggregation: '7',
          )
        end

        before { cached_aggregation }

        it 'assigns a pay_in_advance aggregation' do
          result = count_service.aggregate

          expect(result.pay_in_advance_aggregation).to eq(0)
        end
      end
    end
  end

  describe '.grouped_by_aggregation' do
    let(:grouped_by) { ['agent_name'] }
    let(:agent_names) { %w[aragorn frodo] }
    let(:quantified_event) { nil }
    let(:unique_count_event) { nil }

    context 'when there is persisted event and event added in period' do
      let(:unique_count_events) do
        agent_names.map.with_index do |agent_name, index|
          create(
            :event,
            organization_id: organization.id,
            code: billable_metric.code,
            external_customer_id: customer.external_id,
            external_subscription_id: subscription.external_id,
            timestamp: added_at,
            properties: {
              unique_id: quantified_events[index].external_id,
              agent_name:,
            },
          )
        end
      end

      let(:quantified_events) do
        agent_names.map do |agent_name|
          create(
            :quantified_event,
            organization:,
            added_at:,
            removed_at:,
            external_subscription_id: subscription.external_id,
            billable_metric:,
            grouped_by: { 'agent_name' => agent_name },
          )
        end
      end

      let(:new_quantified_events) do
        agent_names.map do |agent_name|
          create(
            :quantified_event,
            organization:,
            added_at: from_datetime + 10.days,
            removed_at:,
            external_subscription_id: subscription.external_id,
            billable_metric:,
            grouped_by: { 'agent_name' => agent_name },
          )
        end
      end

      let(:new_unique_count_events) do
        agent_names.map.with_index do |agent_name, index|
          create(
            :event,
            organization_id: organization.id,
            code: billable_metric.code,
            external_customer_id: customer.external_id,
            external_subscription_id: subscription.external_id,
            timestamp: from_datetime + 10.days,
            properties: {
              unique_id: new_quantified_events[index].external_id,
              agent_name:,
            },
          )
        end
      end

      before do
        unique_count_events
        new_unique_count_events
      end

      it 'returns the correct result' do
        result = count_service.aggregate

        expect(result.aggregations.count).to eq(2)

        result.aggregations.each do |aggregation|
          expect(aggregation.grouped_by.keys).to include('agent_name')
          expect(aggregation.grouped_by['agent_name']).to eq('frodo').or eq('aragorn')
          expect(aggregation.count).to eq(2)
          expect(aggregation.aggregation).to eq(2)
        end
      end

      context 'when billable metric is not recurring' do
        let(:billable_metric) do
          create(
            :billable_metric,
            organization:,
            aggregation_type: 'unique_count_agg',
            field_name: 'unique_id',
            recurring: false,
          )
        end

        it 'returns only the number of events ingested in the current period' do
          result = count_service.aggregate

          expect(result.aggregations.count).to eq(2)

          result.aggregations.each do |aggregation|
            expect(aggregation.grouped_by.keys).to include('agent_name')
            expect(aggregation.grouped_by['agent_name']).to eq('frodo').or eq('aragorn')
            expect(aggregation.count).to eq(1)
            expect(aggregation.aggregation).to eq(1)
          end
        end
      end
    end

    context 'without events in the period' do
      let(:unique_count_events) do
        agent_names.map.with_index do |agent_name, index|
          create(
            :event,
            organization_id: organization.id,
            code: billable_metric.code,
            external_customer_id: customer.external_id,
            external_subscription_id: subscription.external_id,
            timestamp: added_at,
            properties: {
              unique_id: quantified_events[index].external_id,
              agent_name:,
            },
          )
        end
      end

      let(:quantified_events) do
        agent_names.map do |agent_name|
          create(
            :quantified_event,
            organization:,
            added_at:,
            removed_at:,
            external_subscription_id: subscription.external_id,
            billable_metric:,
            grouped_by: { 'agent_name' => agent_name },
          )
        end
      end

      before { unique_count_events }

      it 'returns only the number of events persisted events' do
        result = count_service.aggregate

        expect(result.aggregations.count).to eq(2)

        result.aggregations.each do |aggregation|
          expect(aggregation.grouped_by.keys).to include('agent_name')
          expect(aggregation.grouped_by['agent_name']).to eq('frodo').or eq('aragorn')
          expect(aggregation.count).to eq(1)
          expect(aggregation.aggregation).to eq(1)
        end
      end
    end

    context 'without quantified events' do
      let(:quantified_event) { nil }
      let(:unique_count_event) { nil }

      it 'returns an empty result' do
        result = count_service.aggregate

        expect(result.aggregations.count).to eq(1)

        aggregation = result.aggregations.first
        expect(aggregation.aggregation).to eq(0)
        expect(aggregation.count).to eq(0)
        expect(aggregation.grouped_by).to eq({ 'agent_name' => nil })
      end
    end

    context 'when current usage context and charge is pay in advance' do
      let(:options) do
        { is_pay_in_advance: true, is_current_usage: true }
      end

      let(:quantified_event) { nil }
      let(:unique_count_event) { nil }

      let(:unique_count_events) do
        agent_names.map.with_index do |agent_name, index|
          create(
            :event,
            organization_id: organization.id,
            code: billable_metric.code,
            external_customer_id: customer.external_id,
            external_subscription_id: subscription.external_id,
            timestamp: added_at,
            properties: {
              unique_id: quantified_events[index].external_id,
              agent_name:,
            },
          )
        end
      end

      let(:quantified_events) do
        agent_names.map do |agent_name|
          create(
            :quantified_event,
            organization:,
            added_at:,
            removed_at:,
            external_subscription_id: subscription.external_id,
            billable_metric:,
            grouped_by: { 'agent_name' => agent_name },
          )
        end
      end

      let(:previous_events) do
        agent_names.map.with_index do |agent_name, index|
          create(
            :event,
            organization_id: organization.id,
            code: billable_metric.code,
            external_customer_id: customer.external_id,
            external_subscription_id: subscription.external_id,
            timestamp: from_datetime + 5.days,
            properties: {
              unique_id: previous_quantified_events[index].external_id,
              agent_name:,
            },
          )
        end
      end

      let(:previous_quantified_events) do
        agent_names.map do |agent_name|
          create(
            :quantified_event,
            organization:,
            added_at: from_datetime + 5.days,
            removed_at:,
            external_id: '000',
            external_subscription_id: subscription.external_id,
            billable_metric:,
            grouped_by: { 'agent_name' => agent_name },
          )
        end
      end

      let(:cached_aggregations) do
        agent_names.map.with_index do |agent_name, index|
          create(
            :cached_aggregation,
            organization:,
            charge:,
            event_id: previous_events[index].id,
            external_subscription_id: subscription.external_id,
            timestamp: previous_events[index].timestamp,
            current_aggregation: '1',
            max_aggregation: '3',
            grouped_by: { 'agent_name' => agent_name },
          )
        end
      end

      before do
        unique_count_events
        cached_aggregations
      end

      it 'returns period maximum as aggregation' do
        result = count_service.aggregate(options:)

        expect(result.aggregations.count).to eq(2)

        result.aggregations.each do |aggregation|
          expect(aggregation.grouped_by.keys).to include('agent_name')
          expect(aggregation.grouped_by['agent_name']).to eq('frodo').or eq('aragorn')
          expect(aggregation.count).to eq(2)
          expect(aggregation.aggregation).to eq(4)
        end
      end

      context 'when cached aggregation does not exist' do
        let(:cached_aggregations) { nil }
        let(:previous_quantified_event) { nil }

        before { billable_metric.update!(recurring: false) }

        it 'returns an empty result' do
          result = count_service.aggregate(options:)

          expect(result.aggregations.count).to eq(1)

          aggregation = result.aggregations.first
          expect(aggregation.aggregation).to eq(0)
          expect(aggregation.count).to eq(0)
          expect(aggregation.grouped_by).to eq({ 'agent_name' => nil })
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
