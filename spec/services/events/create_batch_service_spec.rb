# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Events::CreateBatchService, type: :service do
  subject(:create_batch_service) do
    described_class.new(
      organization:,
      events_params:,
      timestamp: creation_timestamp,
      metadata:,
    )
  end

  let(:organization) { create(:organization) }
  let(:timestamp) { Time.current.to_f }
  let(:code) { 'sum_agg' }
  let(:metadata) { {} }
  let(:creation_timestamp) { Time.current.to_f }

  let(:events_params) do
    events = []
    100.times do
      event = {
        external_customer_id: SecureRandom.uuid,
        external_subscription_id: SecureRandom.uuid,
        code:,
        transaction_id: SecureRandom.uuid,
        properties: { foo: 'bar' },
        timestamp:,
      }

      events << event
    end

    events
  end

  describe '.call' do
    it 'creates all events' do
      result = nil

      aggregate_failures do
        expect { result = create_batch_service.call }.to change(Event, :count).by(100)

        expect(result).to be_success
      end
    end

    it 'enqueues a post processing job' do
      expect { create_batch_service.call }.to have_enqueued_job(Events::PostProcessJob).exactly(100)
    end

    context 'when events count is too big' do
      before do
        events_params.push(
          {
            external_customer_id: SecureRandom.uuid,
            external_subscription_id: SecureRandom.uuid,
            code:,
            transaction_id: SecureRandom.uuid,
            properties: { foo: 'bar' },
            timestamp:,
          },
        )
      end

      it 'returns a too big error' do
        result = nil

        aggregate_failures do
          expect { result = create_batch_service.call }.not_to change(Event, :count)

          expect(result).not_to be_success
          expect(result.error).to be_a(BaseService::ValidationFailure)
          expect(result.error.messages.keys).to include(:events)
          expect(result.error.messages[:events]).to include('too_many_events')
        end
      end
    end
  end
end
