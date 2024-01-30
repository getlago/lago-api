# frozen_string_literal: true

require 'rails_helper'

RSpec.describe QuantifiedEvents::CreateOrUpdateService, type: :service do
  subject(:create_service) do
    described_class.new(event)
  end

  let(:customer) { create(:customer) }
  let(:subscription) { create(:subscription, started_at: event_timestamp - 3.days, customer:) }
  let(:organization) { customer.organization }

  let(:billable_metric) do
    create(
      :billable_metric,
      organization:,
      aggregation_type: 'unique_count_agg',
      field_name: 'item_id',
    )
  end

  let(:event) do
    create(
      :event,
      properties:,
      organization:,
      code: billable_metric.code,
      timestamp: event_timestamp,
      external_customer_id: customer.external_id,
      external_subscription_id: subscription.external_id,
    )
  end

  let(:operation_type) { 'add' }
  let(:external_id) { 'external_id' }
  let(:event_timestamp) { Time.zone.parse('31 Oct 2022 10:02:00') }
  let(:properties) do
    {
      'operation_type' => operation_type,
      billable_metric.field_name => 'ext_12345',
      'region' => 'europe',
    }
  end

  describe '#call' do
    let(:service_result) { create_service.call }

    context 'with add operation type' do
      it 'creates a quantified metric' do
        aggregate_failures do
          expect { service_result }.to change(QuantifiedEvent, :count).by(1)

          expect(service_result).to be_success

          quantified_event = service_result.quantified_event
          expect(quantified_event.organization).to eq(event.organization)
          expect(quantified_event.external_subscription_id).to eq(subscription.external_id)
          expect(quantified_event.external_id).to eq('ext_12345')
          expect(quantified_event.properties).to eq(event.properties)
          expect(quantified_event.added_at.to_s).to eq(event.timestamp.to_s)
        end
      end

      context 'when a quantified metric was removed on the day' do
        let(:quantified_event) do
          create(
            :quantified_event,
            billable_metric:,
            external_subscription_id: subscription.external_id,
            external_id: 'ext_12345',
            removed_at: Time.zone.parse('31 Oct 2022 09:25:00'),
          )
        end

        before { quantified_event }

        it 'reactivate the quantified metric' do
          aggregate_failures do
            expect { service_result }.to change(QuantifiedEvent, :count).by(0)

            expect(service_result).to be_success
            expect(quantified_event.reload.removed_at).to be_nil
          end
        end
      end
    end

    context 'without operation type for unique_count_agg' do
      let(:operation_type) { nil }
      let(:billable_metric) do
        create(
          :billable_metric,
          organization:,
          aggregation_type: 'unique_count_agg',
          field_name: 'item_id',
        )
      end

      it 'creates a quantified metric' do
        aggregate_failures do
          expect { service_result }.to change(QuantifiedEvent, :count).by(1)

          expect(service_result).to be_success

          quantified_event = service_result.quantified_event
          expect(quantified_event.organization).to eq(event.organization)
          expect(quantified_event.external_subscription_id).to eq(subscription.external_id)
          expect(quantified_event.external_id).to eq('ext_12345')
          expect(quantified_event.properties).to eq(event.properties)
          expect(quantified_event.added_at.to_s).to eq(event.timestamp.to_s)
        end
      end
    end

    context 'with remove operation type' do
      let(:quantified_event) do
        create(
          :quantified_event,
          billable_metric:,
          external_subscription_id: subscription.external_id,
          external_id: 'ext_12345',
        )
      end

      let(:operation_type) { 'remove' }

      before { quantified_event }

      it 'updates the active quantified metric' do
        aggregate_failures do
          service_result

          expect(service_result).to be_success

          expect(service_result.quantified_event).to eq(quantified_event)
          expect(service_result.quantified_event.removed_at.to_s).to eq(event.timestamp.to_s)
        end
      end

      context 'with already removed and an active events' do
        before do
          create(
            :quantified_event,
            billable_metric:,
            external_subscription_id: subscription.external_id,
            external_id: 'ext_12345',
            removed_at: (Time.current - 1.hour).to_i,
          )

          quantified_event
        end

        it 'updates the active quantified metric' do
          aggregate_failures do
            service_result

            expect(service_result).to be_success

            expect(service_result.quantified_event).to eq(quantified_event)
            expect(service_result.quantified_event.removed_at.to_s).to eq(event.timestamp.to_s)
          end
        end
      end
    end
  end

  describe '#matching_billable_metric?' do
    it { expect(create_service).to be_matching_billable_metric }

    context 'when billable metric is not a recurring_count or unique_count aggregation' do
      let(:billable_metric) do
        create(
          :billable_metric,
          aggregation_type: 'sum_agg',
          field_name: 'item_id',
        )
      end

      it { expect(create_service).not_to be_matching_billable_metric }
    end
  end

  describe '#process_event?' do
    it { expect(create_service).to be_process_event }

    context 'with an active quantified metric' do
      before do
        create(
          :quantified_event,
          billable_metric:,
          external_subscription_id: subscription.external_id,
          external_id: 'ext_12345',
        )
      end

      it 'does not add quantified event for the same external id' do
        expect(create_service).not_to be_process_event
      end
    end
  end
end
