# frozen_string_literal: true

require 'rails_helper'

RSpec.describe EventsService, type: :service do
  subject(:event_service) { described_class.new }

  let(:organization) { create(:organization) }
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

    context 'with missing or nil arugments' do
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

  describe 'create' do
    let(:create_args) do
      {
        customer_id: customer.customer_id,
        code: 'event_code',
        transaction_id: SecureRandom.uuid,
        properties: { foo: 'bar' },
        timestamp: Time.zone.now.to_i,
      }
    end
    let(:timestamp) { Time.zone.now.to_i }

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
        expect(event.code).to eq('event_code')
        expect(event.timestamp).to be_a(Time)
      end
    end

    context 'when event already exists' do
      let(:existing_event) do
        create(:event, organization: organization, transaction_id: create_args[:transaction_id])
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

    context 'when customer does not exists' do
      let(:create_args) do
        {
          customer_id: SecureRandom.uuid,
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
        expect(result.error).to eq('customer does not exists')
      end
    end

    context 'when properties are empty' do
      let(:create_args) do
        {
          customer_id: customer.customer_id,
          code: 'event_code',
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
          expect(event.code).to eq('event_code')
          expect(event.timestamp).to be_a(Time)
          expect(event.properties).to eq({})
        end
      end
    end
  end
end
