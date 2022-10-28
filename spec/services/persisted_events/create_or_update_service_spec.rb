# frozen_string_literal: true

require 'rails_helper'

RSpec.describe PersistedEvents::CreateOrUpdateService, type: :service do
  subject(:create_service) do
    described_class.new(event)
  end

  let(:billable_metric) do
    create(
      :billable_metric,
      aggregation_type: 'recurring_count_agg',
      field_name: 'item_id',
    )
  end

  let(:event) do
    create(
      :event,
      properties: properties,
      organization: billable_metric.organization,
      code: billable_metric.code,
    )
  end

  let(:operation_type) { 'add' }
  let(:external_id) { 'external_id' }
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
      it 'creates a persisted metric' do
        aggregate_failures do
          expect { service_result }.to change(PersistedEvent, :count).by(1)

          expect(service_result).to be_success

          persisted_event = service_result.persisted_event
          expect(persisted_event.customer).to eq(event.customer)
          expect(persisted_event.external_subscription_id).to eq(event.subscription.external_id)
          expect(persisted_event.external_id).to eq('ext_12345')
          expect(persisted_event.properties).to eq(event.properties)
          expect(persisted_event.added_at.to_s).to eq(event.timestamp.to_s)
        end
      end
    end

    context 'with remove operation type' do
      let(:persisted_event) do
        create(
          :persisted_event,
          customer: event.customer,
          billable_metric: billable_metric,
          external_subscription_id: event.subscription.external_id,
          external_id: 'ext_12345',
        )
      end

      let(:operation_type) { 'remove' }

      before { persisted_event }

      it 'updates the active persisted metric' do
        aggregate_failures do
          service_result

          expect(service_result).to be_success

          expect(service_result.persisted_event).to eq(persisted_event)
          expect(service_result.persisted_event.removed_at.to_s).to eq(event.timestamp.to_s)
        end
      end

      context 'with already removed and an active events' do
        before do
          create(
            :persisted_event,
            customer: event.customer,
            billable_metric: billable_metric,
            external_subscription_id: event.subscription.external_id,
            external_id: 'ext_12345',
            removed_at: (Time.current - 1.hour).to_i,
          )

          persisted_event
        end

        it 'updates the active persisted metric' do
          aggregate_failures do
            service_result

            expect(service_result).to be_success

            expect(service_result.persisted_event).to eq(persisted_event)
            expect(service_result.persisted_event.removed_at.to_s).to eq(event.timestamp.to_s)
          end
        end
      end
    end
  end

  describe '#matching_billable_metric?' do
    it { expect(create_service).to be_matching_billable_metric }

    context 'when billable metric is not a recurring count aggregation' do
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
end
