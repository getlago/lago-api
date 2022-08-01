# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Events::CreateBatchService, type: :service do
  subject(:create_batch_service) { described_class.new }

  let(:organization) { create(:organization) }
  let(:billable_metric)  { create(:billable_metric, organization: organization) }
  let(:customer) { create(:customer, organization: organization) }

  describe '.validate_batch_params' do
    let(:event_arguments) do
      {
        transaction_id: SecureRandom.uuid,
        subscription_ids: %w[id1 id2],
        code: 'foo',
      }
    end

    it 'validates the presence of the mandatory arguments' do
      result = create_batch_service.validate_batch_params(params: event_arguments)

      expect(result).to be_success
    end

    context 'with missing or nil arguments' do
      let(:event_arguments) do
        {
          code: nil,
        }
      end

      it 'returns an error' do
        result = create_batch_service.validate_batch_params(params: event_arguments)

        expect(result).not_to be_success

        aggregate_failures do
          expect(result.error_code).to eq('missing_mandatory_param')
          expect(result.error_details).to include(:transaction_id)
          expect(result.error_details).to include(:code)
          expect(result.error_details).to include(:subscription_ids)
        end
      end
    end
  end

  describe 'call' do
    let(:transaction_id) { SecureRandom.uuid }
    let(:subscription) { create(:active_subscription, customer: customer, organization: organization) }
    let(:subscription2) { create(:active_subscription, customer: customer, organization: organization) }

    let(:create_args) do
      {
        subscription_ids: [subscription.id, subscription2.id],
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
    end

    context 'when event for one subscription already exists' do
      let(:existing_event) do
        create(:event,
               organization: organization,
               transaction_id: create_args[:transaction_id],
               subscription_id: subscription.id
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

    context 'when customer cannot be found' do
      let(:create_args) do
        {
          subscription_ids: ['invalid'],
          code: billable_metric.code,
          transaction_id: transaction_id,
          properties: { foo: 'bar' },
          timestamp: Time.zone.now.to_i,
        }
      end

      it 'fails' do
        result = create_batch_service.call(
          organization: organization,
          params: create_args,
          timestamp: timestamp,
          metadata: {},
        )

        expect(result).not_to be_success
        expect(result.error).to eq('customer cannot be found')
      end

      it 'enqueues a SendWebhookJob' do
        expect do
          create_batch_service.call(
            organization: organization,
            params: create_args,
            timestamp: timestamp,
            metadata: {},
          )
        end.to have_enqueued_job(SendWebhookJob)
      end
    end

    context 'when subscription_ids is not given' do
      let(:create_args) do
        {
          code: billable_metric.code,
          transaction_id: transaction_id,
          properties: { foo: 'bar' },
          timestamp: Time.zone.now.to_i,
        }
      end

      it 'fails' do
        result = create_batch_service.call(
          organization: organization,
          params: create_args,
          timestamp: timestamp,
          metadata: {},
        )

        expect(result).not_to be_success
        expect(result.error).to eq('subscription does not exist or is not given')
      end

      it 'enqueues a SendWebhookJob' do
        expect do
          create_batch_service.call(
            organization: organization,
            params: create_args,
            timestamp: timestamp,
            metadata: {},
          )
        end.to have_enqueued_job(SendWebhookJob)
      end
    end

    context 'when there are two active subscriptions and one subscription_id is invalid' do
      let(:create_args) do
        {
          subscription_ids: [subscription.id, 'invalid'],
          code: billable_metric.code,
          transaction_id: transaction_id,
          properties: { foo: 'bar' },
          timestamp: Time.zone.now.to_i,
        }
      end

      it 'fails' do
        result = create_batch_service.call(
          organization: organization,
          params: create_args,
          timestamp: timestamp,
          metadata: {},
        )

        expect(result).not_to be_success
        expect(result.error).to eq('subscription_id is invalid')
      end

      it 'enqueues a SendWebhookJob' do
        expect do
          create_batch_service.call(
            organization: organization,
            params: create_args,
            timestamp: timestamp,
            metadata: {},
          )
        end.to have_enqueued_job(SendWebhookJob)
      end
    end

    context 'when code does not exist' do
      let(:create_args) do
        {
          subscription_ids: [subscription.id, subscription2.id],
          code: 'invalid',
          transaction_id: transaction_id,
          properties: { foo: 'bar' },
          timestamp: Time.zone.now.to_i,
        }
      end

      it 'fails' do
        result = create_batch_service.call(
          organization: organization,
          params: create_args,
          timestamp: timestamp,
          metadata: {},
        )

        expect(result).not_to be_success
        expect(result.error).to eq('code does not exist')
      end

      it 'enqueues a SendWebhookJob' do
        expect do
          create_batch_service.call(
            organization: organization,
            params: create_args,
            timestamp: timestamp,
            metadata: {},
          )
        end.to have_enqueued_job(SendWebhookJob)
      end
    end
  end
end
