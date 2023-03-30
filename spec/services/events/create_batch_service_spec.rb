# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Events::CreateBatchService, type: :service do
  subject(:create_batch_service) { described_class.new }

  let(:organization) { create(:organization) }
  let(:billable_metric) { create(:billable_metric, organization: organization) }
  let(:customer) { create(:customer, organization: organization) }
  let(:subscription) { create(:active_subscription, customer:, organization:) }
  let(:subscription2) { create(:active_subscription, customer:, organization:) }

  before do
    subscription
    subscription2
  end

  describe '#validate_params' do
    let(:event_arguments) do
      {
        transaction_id: SecureRandom.uuid,
        external_subscription_ids: [subscription.external_id, subscription2.external_id],
        code: billable_metric.code,
      }
    end

    it 'successfully validates event arguments' do
      result = create_batch_service.validate_params(organization:, params: event_arguments)

      expect(result).to be_success
    end

    context 'with missing external_subscription_ids field' do
      let(:event_arguments) do
        {
          transaction_id: SecureRandom.uuid,
          code: billable_metric.code,
        }
      end

      it 'returns an error' do
        result = create_batch_service.validate_params(organization:, params: event_arguments)

        aggregate_failures do
          expect(result).not_to be_success
          expect(result.error).to be_a(BaseService::NotFoundFailure)
          expect(result.error.error_code).to eq('subscription_not_found')
        end
      end
    end

    context 'with invalid external_subscription_id value' do
      let(:event_arguments) do
        {
          transaction_id: SecureRandom.uuid,
          external_subscription_ids: [subscription.external_id, subscription2.external_id, 'invalid'],
          code: billable_metric.code,
        }
      end

      it 'returns an error' do
        result = create_batch_service.validate_params(organization:, params: event_arguments)

        aggregate_failures do
          expect(result).not_to be_success
          expect(result.error).to be_a(BaseService::NotFoundFailure)
          expect(result.error.error_code).to eq('subscription_not_found')
        end
      end
    end

    context 'with invalid customer reference' do
      let(:subscription3) { create(:active_subscription) }
      let(:event_arguments) do
        {
          transaction_id: SecureRandom.uuid,
          external_subscription_ids: [subscription3.external_id, subscription2.external_id],
          code: billable_metric.code,
        }
      end

      before { subscription3 }

      it 'returns an error' do
        result = create_batch_service.validate_params(organization:, params: event_arguments)

        aggregate_failures do
          expect(result).not_to be_success
          expect(result.error).to be_a(BaseService::NotFoundFailure)
          expect(result.error.error_code).to eq('customer_not_found')
        end
      end
    end

    context 'with invalid billable metric code' do
      let(:event_arguments) do
        {
          transaction_id: SecureRandom.uuid,
          external_subscription_ids: [subscription.external_id, subscription2.external_id],
          code: 'foo',
        }
      end

      it 'returns an error' do
        result = create_batch_service.validate_params(organization:, params: event_arguments)

        aggregate_failures do
          expect(result).not_to be_success
          expect(result.error).to be_a(BaseService::NotFoundFailure)
          expect(result.error.error_code).to eq('billable_metric_not_found')
        end
      end
    end

    context 'with invalid properties' do
      let(:billable_metric) { create(:sum_billable_metric, organization:) }
      let(:event_arguments) do
        {
          transaction_id: SecureRandom.uuid,
          external_subscription_ids: [subscription.external_id, subscription2.external_id],
          code: billable_metric.code,
          properties: {
            item_id: 'test',
          },
        }
      end

      it 'returns an error' do
        result = create_batch_service.validate_params(organization:, params: event_arguments)

        aggregate_failures do
          expect(result).not_to be_success
          expect(result.error).to be_a(BaseService::ValidationFailure)
          expect(result.error.messages.keys).to include(:properties)
          expect(result.error.messages[:properties]).to include('value_is_not_valid_number')
        end
      end
    end
  end

  describe '#call' do
    let(:transaction_id) { SecureRandom.uuid }
    let(:subscription) { create(:active_subscription, customer: customer, organization: organization) }
    let(:subscription2) { create(:active_subscription, customer: customer, organization: organization) }

    let(:create_args) do
      {
        external_subscription_ids: [subscription.external_id, subscription2.external_id],
        code: billable_metric.code,
        transaction_id: transaction_id,
        properties: { foo: 'bar' },
        timestamp: Time.zone.now.to_i,
      }
    end
    let(:timestamp) { Time.zone.now.to_i }

    before do
      subscription
      subscription2
    end

    context 'when customer has two active subscription' do
      it 'creates a new event for each subscription' do
        result = create_batch_service.call(
          organization: organization,
          params: create_args,
          timestamp: timestamp,
          metadata: {},
        )

        expect(result).to be_success

        events = result.events

        aggregate_failures do
          expect(events.first.customer_id).to eq(customer.id)
          expect(events.first.organization_id).to eq(organization.id)
          expect(events.first.code).to eq(billable_metric.code)
          expect(events.first.subscription_id).to eq(subscription.id)
          expect(events.first.transaction_id).to eq(transaction_id)
          expect(events.last.customer_id).to eq(customer.id)
          expect(events.last.organization_id).to eq(organization.id)
          expect(events.last.code).to eq(billable_metric.code)
          expect(events.last.subscription_id).to eq(subscription2.id)
          expect(events.last.transaction_id).to eq(transaction_id)
        end
      end

      context 'when event matches a recurring billable metric' do
        let(:billable_metric) do
          create(
            :billable_metric,
            organization: customer.organization,
            aggregation_type: 'recurring_count_agg',
            field_name: 'item_id',
          )
        end

        let(:create_args) do
          {
            external_subscription_ids: [subscription.external_id, subscription2.external_id],
            code: billable_metric.code,
            transaction_id: SecureRandom.uuid,
            properties: {
              billable_metric.field_name => 'ext_12345',
              'operation_type' => 'add',
            },
            timestamp: Time.zone.now.to_i,
          }
        end

        it 'creates a persisted metric' do
          expect do
            create_batch_service.call(
              organization: organization,
              params: create_args,
              timestamp: timestamp,
              metadata: {},
            )
          end.to change(PersistedEvent, :count).by(2)
        end
      end
    end

    context 'when event for one subscription already exists' do
      let(:existing_event) do
        create(
          :event,
          organization: organization,
          transaction_id: create_args[:transaction_id],
          subscription_id: subscription.id,
        )
      end

      before { existing_event }

      it 'does not duplicate existing event' do
        expect do
          create_batch_service.call(
            organization: organization,
            params: create_args,
            timestamp: timestamp,
            metadata: {},
          )
        end.to change { organization.events.count }.by(1)
      end
    end
  end
end
