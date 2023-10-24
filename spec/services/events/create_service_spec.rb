# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Events::CreateService, type: :service do
  subject(:create_service) do
    described_class.new(
      organization:,
      params: create_args,
      timestamp: creation_timestamp,
      metadata:,
    )
  end

  let(:organization) { create(:organization) }

  let(:code) { 'sum_agg' }
  let(:external_customer_id) { SecureRandom.uuid }
  let(:external_subscription_id) { SecureRandom.uuid }
  let(:timestamp) { Time.current.to_f }
  let(:transaction_id) { SecureRandom.uuid }

  let(:creation_timestamp) { Time.current.to_f }

  let(:create_args) do
    {
      external_customer_id:,
      external_subscription_id:,
      code:,
      transaction_id:,
      properties: { foo: 'bar' },
      timestamp:,
    }
  end

  let(:metadata) { {} }

  describe '#call' do
    it 'creates an event' do
      result = nil

      aggregate_failures do
        expect { result = create_service.call }.to change(Event, :count).by(1)

        expect(result).to be_success
        expect(result.event).to have_attributes(
          external_customer_id:,
          external_subscription_id:,
          transaction_id:,
          code:,
          timestamp: Time.zone.at(timestamp),
          properties: { 'foo' => 'bar' },
        )
      end
    end

    it 'enqueues a post processing job' do
      expect { create_service.call }.to have_enqueued_job(Events::PostProcessJob)
    end

    context 'when event already exists' do
      let(:existing_event) do
        create(
          :event,
          organization:,
          transaction_id: create_args[:transaction_id],
          external_subscription_id:,
        )
      end

      before { existing_event }

      it 'returns an error' do
        result = 0

        aggregate_failures do
          expect { result = create_service.call }.not_to change(Event, :count)

          expect(result).not_to be_success
          expect(result.error).to be_a(BaseService::ValidationFailure)
          expect(result.error.messages.keys).to include(:transaction_id)
          expect(result.error.messages[:transaction_id]).to include('value_already_exist')
        end
      end
    end

    context 'when timestamp is not present in the payload' do
      let(:timestamp) { nil }

      it 'creates an event by setting the timestamp to the current datetime' do
        result = create_service.call

        expect(result).to be_success
        expect(result.event.timestamp).to eq(Time.zone.at(creation_timestamp))
      end
    end

    context 'when timestamp is given as string' do
      let(:timestamp) { Time.current.to_f.to_s }

      it 'creates an event by setting timestamp' do
        result = create_service.call

        expect(result).to be_success
        expect(result.event.timestamp).to eq(Time.zone.at(timestamp.to_f))
      end
    end

    context 'when timestamp is sent with decimal precision' do
      let(:timestamp) { DateTime.parse('2023-09-04T15:45:12.344Z').to_f }

      it 'creates an event by keeping the millisecond precision' do
        result = create_service.call

        expect(result).to be_success
        expect(result.event.timestamp.iso8601(3)).to eq('2023-09-04T15:45:12.344Z')
      end
    end

    context 'when kafka is configured' do
      let(:karafka_producer) { instance_double(WaterDrop::Producer) }

      before do
        ENV['LAGO_KAFKA_BOOTSTRAP_SERVERS'] = 'kafka'
      end

      it 'produces the event on kafka' do
        allow(Karafka).to receive(:producer).and_return(karafka_producer)
        allow(karafka_producer).to receive(:produce_sync)

        create_service.call

        expect(karafka_producer).to have_received(:produce_sync)
      end
    end
  end
end
