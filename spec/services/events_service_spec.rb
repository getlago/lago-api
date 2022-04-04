# frozen_string_literal: true

require 'rails_helper'

RSpec.describe EventsService, type: :service do
  subject(:event_service) { described_class.new }

  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization: organization) }

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

    it 'creates a new event' do
      result = event_service.create(
        organization: organization,
        params: create_args,
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
        )

        expect(result).not_to be_success
        expect(result.error).to eq('customer does not exists')
      end
    end
  end
end
