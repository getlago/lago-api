# frozen_string_literal: true

require 'rails_helper'

RSpec.describe BillableMetrics::Aggregations::RecurringCountService, type: :service do
  subject(:recurring_service) do
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

  let(:subscription) do
    create(
      :subscription,
      started_at:,
      subscription_at:,
      billing_time: :anniversary,
    )
  end

  let(:subscription_at) { DateTime.parse('2022-06-09') }
  let(:started_at) { subscription_at }
  let(:organization) { subscription.organization }
  let(:customer) { subscription.customer }
  let(:group) { nil }

  let(:billable_metric) do
    create(
      :billable_metric,
      organization:,
      aggregation_type: 'recurring_count_agg',
      field_name: 'unique_id',
    )
  end

  let(:from_datetime) { DateTime.parse('2022-07-09 00:00:00 UTC') }
  let(:to_datetime) { DateTime.parse('2022-08-08 23:59:59 UTC') }

  let(:added_at) { from_datetime - 1.month }
  let(:removed_at) { nil }
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

  before { quantified_event }

  describe '#aggregate' do
    let(:result) { recurring_service.aggregate }

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

        it 'returns the prorata of the full duration' do
          expect(result.aggregation).to eq(16.fdiv(31).ceil(5))
        end
      end

      context 'when subscription was started in the period' do
        let(:started_at) { DateTime.parse('2022-08-01') }
        let(:from_datetime) { started_at }

        it 'returns the prorata of the full duration' do
          expect(result.aggregation).to eq(8.fdiv(31).ceil(5))
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
  end

  describe '#breakdown' do
    let(:result) { recurring_service.breakdown.breakdown }

    context 'with persisted metric on full period' do
      it 'returns the detail the persisted metrics' do
        aggregate_failures do
          expect(result.count).to eq(1)

          item = result.first
          expect(item.date.to_s).to eq(from_datetime.to_date.to_s)
          expect(item.action).to eq('add')
          expect(item.count).to eq(1)
          expect(item.duration).to eq(31)
          expect(item.total_duration).to eq(31)
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
        let(:to_datetime) { DateTime.parse('2022-07-24 23:59:59') }

        it 'returns the detail the persisted metrics' do
          aggregate_failures do
            expect(result.count).to eq(1)

            item = result.first
            expect(item.date.to_s).to eq(from_datetime.to_date.to_date.to_s)
            expect(item.action).to eq('add')
            expect(item.count).to eq(1)
            expect(item.duration).to eq(16)
            expect(item.total_duration).to eq(31)
          end
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

        it 'returns the detail the persisted metrics' do
          aggregate_failures do
            expect(result.count).to eq(1)

            item = result.first
            expect(item.date.to_s).to eq(from_datetime.to_date.to_s)
            expect(item.action).to eq('add')
            expect(item.count).to eq(1)
            expect(item.duration).to eq(16)
            expect(item.total_duration).to eq(31)
          end
        end

        context 'with calendar subscription and pay in advance' do
          let(:subscription) do
            create(
              :subscription,
              started_at:,
              subscription_at:,
              billing_time: :calendar,
              terminated_at: to_datetime,
              status: :terminated,
            )
          end

          before { subscription.plan.update!(pay_in_advance: true) }

          it 'returns the detail the persisted metrics' do
            aggregate_failures do
              expect(result.count).to eq(1)

              item = result.first
              expect(item.date.to_s).to eq(from_datetime.to_date.to_s)
              expect(item.action).to eq('add')
              expect(item.count).to eq(1)
              expect(item.duration).to eq(16)
              expect(item.total_duration).to eq(31)
            end
          end
        end
      end

      context 'when subscription was started in the period' do
        let(:started_at) { DateTime.parse('2022-08-01') }
        let(:from_datetime) { started_at }

        it 'returns the detail the persisted metrics' do
          aggregate_failures do
            expect(result.count).to eq(1)

            item = result.first
            expect(item.date.to_s).to eq(from_datetime.to_date.to_s)
            expect(item.action).to eq('add')
            expect(item.count).to eq(1)
            expect(item.duration).to eq(8)
            expect(item.total_duration).to eq(31)
          end
        end
      end
    end

    context 'with persisted metrics added in the period' do
      let(:added_at) { from_datetime + 15.days }

      it 'returns the detail the persisted metrics' do
        aggregate_failures do
          expect(result.count).to eq(1)

          item = result.first
          expect(item.date.to_s).to eq(added_at.to_date.to_s)
          expect(item.action).to eq('add')
          expect(item.count).to eq(1)
          expect(item.duration).to eq(16)
          expect(item.total_duration).to eq(31)
        end
      end

      context 'when added on the first day of the period' do
        let(:added_at) { from_datetime }

        it 'returns the detail the persisted metrics' do
          aggregate_failures do
            expect(result.count).to eq(1)

            item = result.first
            expect(item.date.to_s).to eq(from_datetime.to_date.to_s)
            expect(item.action).to eq('add')
            expect(item.count).to eq(1)
            expect(item.duration).to eq(31)
            expect(item.total_duration).to eq(31)
          end
        end
      end
    end

    context 'with persisted metrics terminated in the period' do
      let(:removed_at) { to_datetime - 15.days }

      it 'returns the detail the persisted metrics' do
        aggregate_failures do
          expect(result.count).to eq(1)

          item = result.first
          expect(item.date.to_s).to eq(removed_at.to_date.to_s)
          expect(item.action).to eq('remove')
          expect(item.count).to eq(1)
          expect(item.duration).to eq(16)
          expect(item.total_duration).to eq(31)
        end
      end

      context 'when removed on the last day of the period' do
        let(:removed_at) { to_datetime }

        it 'returns the detail the persisted metrics' do
          aggregate_failures do
            expect(result.count).to eq(1)

            item = result.first
            expect(item.date.to_s).to eq(to_datetime.to_date.to_s)
            expect(item.action).to eq('remove')
            expect(item.count).to eq(1)
            expect(item.duration).to eq(31)
            expect(item.total_duration).to eq(31)
          end
        end
      end
    end

    context 'with persisted metrics added and terminated in the period' do
      let(:added_at) { from_datetime + 1.day }
      let(:removed_at) { to_datetime - 1.day }

      it 'returns the detail the persisted metrics' do
        aggregate_failures do
          expect(result.count).to eq(1)

          item = result.first
          expect(item.date.to_s).to eq(added_at.to_date.to_s)
          expect(item.action).to eq('add_and_removed')
          expect(item.count).to eq(1)
          expect(item.duration).to eq(29)
          expect(item.total_duration).to eq(31)
        end
      end

      context 'when added and removed the same day' do
        let(:added_at) { from_datetime + 1.day }
        let(:removed_at) { added_at }

        it 'returns the detail the persisted metrics' do
          aggregate_failures do
            expect(result.count).to eq(1)

            item = result.first
            expect(item.date.to_s).to eq(added_at.to_date.to_s)
            expect(item.action).to eq('add_and_removed')
            expect(item.count).to eq(1)
            expect(item.duration).to eq(1)
            expect(item.total_duration).to eq(31)
          end
        end
      end
    end

    context 'when group is given' do
      let(:group) do
        create(:group, billable_metric_id: billable_metric.id, key: 'region', value: 'europe')
      end

      before do
        create(
          :quantified_event,
          customer:,
          added_at:,
          removed_at:,
          external_subscription_id: subscription.external_id,
          billable_metric:,
          properties: {
            total_count: 12,
            region: 'europe',
          },
        )

        create(
          :quantified_event,
          customer:,
          added_at:,
          removed_at:,
          external_subscription_id: subscription.external_id,
          billable_metric:,
          properties: {
            total_count: 8,
            region: 'europe',
          },
        )

        create(
          :quantified_event,
          customer:,
          added_at:,
          removed_at:,
          external_subscription_id: subscription.external_id,
          billable_metric:,
          properties: {
            total_count: 8,
            region: 'africa',
          },
        )
      end

      it 'aggregates the events' do
        result = recurring_service.aggregate

        expect(result.aggregation).to eq(2)
      end
    end
  end
end
