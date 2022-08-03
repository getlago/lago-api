# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Events::CreateService, type: :service do
  subject(:create_service) { described_class.new }

  let(:organization) { create(:organization) }
  let(:billable_metric) { create(:billable_metric, organization: organization) }
  let(:customer) { create(:customer, organization: organization) }

  describe '#validate_params' do
    let(:params) do
      {
        transaction_id: SecureRandom.uuid,
        customer_id: SecureRandom.uuid,
        code: 'foo',
      }
    end

    it 'validates the presence of the mandatory arguments' do
      result = create_service.validate_params(params: params)

      expect(result).to be_success
    end

    context 'with missing or nil arguments' do
      let(:params) do
        {
          customer_id: SecureRandom.uuid,
          code: nil,
        }
      end

      it 'returns an error' do
        result = create_service.validate_params(params: params)

        expect(result).not_to be_success

        aggregate_failures do
          expect(result.error_code).to eq('missing_mandatory_param')
          expect(result.error_details).to include(:transaction_id)
          expect(result.error_details).to include(:code)
        end
      end
    end

    context 'when customer_id and subscription_id but multiple subscriptions' do
      let(:subscription) { create(:subscription, customer: customer) }
      let(:params) do
        {
          transaction_id: SecureRandom.uuid,
          customer_id: customer.customer_id,
          subscription_id: subscription.id,
          code: 'code'
        }
      end

      before do
        create(:subscription, customer: customer)
      end

      it 'does not return any error' do
        result = create_service.validate_params(params: params)

        expect(result).to be_success
      end
    end

    context 'when only customer_id but multiple subscriptions' do
      let(:params) do
        {
          transaction_id: SecureRandom.uuid,
          customer_id: customer.customer_id,
          code: 'code'
        }
      end

      before do
        2.times { create(:subscription, customer: customer) }
      end

      it 'returns an error' do
        result = create_service.validate_params(params: params)

        expect(result).not_to be_success

        aggregate_failures do
          expect(result.error_code).to eq('missing_mandatory_param')
          expect(result.error_details).to include(:subscription_id)
        end
      end
    end
  end

  describe '#call' do
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
        result = create_service.call(
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
        result = create_service.call(
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
        result = create_service.call(
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
          create_service.call(
            organization: organization,
            params: create_args,
            timestamp: timestamp,
            metadata: {},
          )
        end.not_to change { organization.events.count }
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
        result = create_service.call(
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
end
