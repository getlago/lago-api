# frozen_string_literal: true

require 'rails_helper'

RSpec.describe EventsService, type: :service do
  subject(:event_service) { described_class.new }

  let(:organization) { create(:organization) }
  let(:billable_metric)  { create(:billable_metric, organization: organization) }
  let(:customer) { create(:customer, organization: organization) }

  describe '.validate_params' do
    let(:event_arguments) do
      {
        transaction_id: SecureRandom.uuid,
        customer_id: SecureRandom.uuid,
        code: 'foo',
      }
    end

    it 'validates the presence of the mandatory arguments' do
      result = event_service.validate_params(params: event_arguments)

      expect(result).to be_success
    end

    context 'with missing or nil arguments' do
      let(:event_arguments) do
        {
          customer_id: SecureRandom.uuid,
          code: nil,
        }
      end

      it 'returns an error' do
        result = event_service.validate_params(params: event_arguments)

        expect(result).not_to be_success

        aggregate_failures do
          expect(result.error_code).to eq('missing_mandatory_param')
          expect(result.error_details).to include(:transaction_id)
          expect(result.error_details).to include(:code)
        end
      end
    end
  end

  describe '.validate_batch_params' do
    let(:event_arguments) do
      {
        transaction_id: SecureRandom.uuid,
        subscription_ids: %w[id1 id2],
        code: 'foo',
      }
    end

    it 'validates the presence of the mandatory arguments' do
      result = event_service.validate_batch_params(params: event_arguments)

      expect(result).to be_success
    end

    context 'with missing or nil arguments' do
      let(:event_arguments) do
        {
          code: nil,
        }
      end

      it 'returns an error' do
        result = event_service.validate_batch_params(params: event_arguments)

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

  describe 'create' do
    let(:subscription) { create(:active_subscription, customer: customer, organization: organization) }

    let(:create_args) do
      {
        customer_id: customer.customer_id,
        code: billable_metric.code,
        transaction_id: SecureRandom.uuid,
        properties: { foo: 'bar' },
        timestamp: Time.zone.now.to_i,
      }
    end
    let(:timestamp) { Time.zone.now.to_i }

    before { subscription }

    context 'when customer has only one active subscription and subscription is not given' do
      it 'creates a new event and assigns subscription' do
        result = event_service.create(
          organization: organization,
          params: create_args,
          timestamp: timestamp,
          metadata: {},
        )

        expect(result).to be_success

        event = result.event

        aggregate_failures do
          expect(event.customer_id).to eq(customer.id)
          expect(event.organization_id).to eq(organization.id)
          expect(event.code).to eq(billable_metric.code)
          expect(event.subscription_id).to eq(subscription.id)
          expect(event.timestamp).to be_a(Time)
        end
      end
    end

    context 'when customer has only one active subscription and customer is not given' do
      let(:create_args) do
        {
          code: billable_metric.code,
          transaction_id: SecureRandom.uuid,
          subscription_id: subscription.id,
          properties: { foo: 'bar' },
          timestamp: Time.zone.now.to_i,
        }
      end

      it 'creates a new event and assigns customer' do
        result = event_service.create(
          organization: organization,
          params: create_args,
          timestamp: timestamp,
          metadata: {},
        )

        expect(result).to be_success

        event = result.event

        aggregate_failures do
          expect(event.customer_id).to eq(customer.id)
          expect(event.organization_id).to eq(organization.id)
          expect(event.code).to eq(billable_metric.code)
          expect(event.subscription_id).to eq(subscription.id)
          expect(event.timestamp).to be_a(Time)
        end
      end
    end

    context 'when customer has two active subscriptions' do
      let(:subscription2) { create(:active_subscription, customer: customer, organization: organization) }

      let(:create_args) do
        {
          code: billable_metric.code,
          transaction_id: SecureRandom.uuid,
          subscription_id: subscription2.id,
          properties: { foo: 'bar' },
          timestamp: Time.zone.now.to_i,
        }
      end

      before { subscription2 }

      it 'creates a new event for correct subscription' do
        result = event_service.create(
          organization: organization,
          params: create_args,
          timestamp: timestamp,
          metadata: {},
        )

        expect(result).to be_success

        event = result.event

        aggregate_failures do
          expect(event.subscription_id).to eq(subscription2.id)
        end
      end
    end

    context 'when event already exists' do
      let(:existing_event) do
        create(:event,
               organization: organization,
               transaction_id: create_args[:transaction_id],
               subscription_id: subscription.id
        )
      end

      before { existing_event }

      it 'returns existing event' do
        expect do
          event_service.create(
            organization: organization,
            params: create_args,
            timestamp: timestamp,
            metadata: {},
          )
        end.not_to change { organization.events.count }
      end
    end

    context 'when customer cannot be found' do
      let(:create_args) do
        {
          customer_id: SecureRandom.uuid,
          code: billable_metric.code,
          transaction_id: SecureRandom.uuid,
          properties: { foo: 'bar' },
          timestamp: Time.zone.now.to_i,
        }
      end

      it 'fails' do
        result = event_service.create(
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
          event_service.create(
            organization: organization,
            params: create_args,
            timestamp: timestamp,
            metadata: {},
          )
        end.to have_enqueued_job(SendWebhookJob)
      end
    end

    context 'when there are two active subscriptions and subscription_id is not given' do
      let(:subscription2) { create(:active_subscription, customer: customer, organization: organization) }

      before { subscription2 }

      it 'fails' do
        result = event_service.create(
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
          event_service.create(
            organization: organization,
            params: create_args,
            timestamp: timestamp,
            metadata: {},
          )
        end.to have_enqueued_job(SendWebhookJob)
      end
    end

    context 'when there are two active subscriptions and subscription_id is invalid' do
      let(:subscription2) { create(:active_subscription, customer: customer, organization: organization) }
      let(:create_args) do
        {
          code: billable_metric.code,
          transaction_id: SecureRandom.uuid,
          subscription_id: SecureRandom.uuid,
          customer_id: customer.customer_id,
          properties: { foo: 'bar' },
          timestamp: Time.zone.now.to_i,
        }
      end

      before { subscription2 }

      it 'fails' do
        result = event_service.create(
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
          event_service.create(
            organization: organization,
            params: create_args,
            timestamp: timestamp,
            metadata: {},
          )
        end.to have_enqueued_job(SendWebhookJob)
      end
    end

    context 'when there is one active subscriptions and subscription_id is invalid' do
      let(:create_args) do
        {
          code: billable_metric.code,
          transaction_id: SecureRandom.uuid,
          subscription_id: SecureRandom.uuid,
          customer_id: customer.customer_id,
          properties: { foo: 'bar' },
          timestamp: Time.zone.now.to_i,
        }
      end

      it 'fails' do
        result = event_service.create(
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
          event_service.create(
            organization: organization,
            params: create_args,
            timestamp: timestamp,
            metadata: {},
          )
        end.to have_enqueued_job(SendWebhookJob)
      end
    end

    context 'when there is only customer_id and subscription cannot be attached' do
      let(:subscription) { nil }
      let(:create_args) do
        {
          code: billable_metric.code,
          transaction_id: SecureRandom.uuid,
          customer_id: customer.customer_id,
          properties: { foo: 'bar' },
          timestamp: Time.zone.now.to_i,
        }
      end

      it 'fails' do
        result = event_service.create(
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
          event_service.create(
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
          customer_id: customer.customer_id,
          code: 'event_code',
          transaction_id: SecureRandom.uuid,
          properties: { foo: 'bar' },
          timestamp: Time.zone.now.to_i,
        }
      end

      it 'fails' do
        result = event_service.create(
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
          event_service.create(
            organization: organization,
            params: create_args,
            timestamp: timestamp,
            metadata: {},
          )
        end.to have_enqueued_job(SendWebhookJob)
      end
    end

    context 'when properties are empty' do
      let(:create_args) do
        {
          customer_id: customer.customer_id,
          code: billable_metric.code,
          transaction_id: SecureRandom.uuid,
          timestamp: Time.zone.now.to_i,
        }
      end

      it 'creates a new event' do
        result = event_service.create(
          organization: organization,
          params: create_args,
          timestamp: timestamp,
          metadata: {},
        )

        expect(result).to be_success

        event = result.event

        aggregate_failures do
          expect(event.customer_id).to eq(customer.id)
          expect(event.organization_id).to eq(organization.id)
          expect(event.code).to eq(billable_metric.code)
          expect(event.subscription_id).to eq(subscription.id)
          expect(event.timestamp).to be_a(Time)
          expect(event.properties).to eq({})
        end
      end
    end
  end

  describe 'batch_create' do
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
        result = event_service.batch_create(
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
          event_service.batch_create(
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
        result = event_service.batch_create(
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
          event_service.batch_create(
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
        result = event_service.batch_create(
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
          event_service.batch_create(
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
        result = event_service.batch_create(
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
          event_service.batch_create(
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
        result = event_service.batch_create(
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
          event_service.batch_create(
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
