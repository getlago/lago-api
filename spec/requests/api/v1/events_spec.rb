# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Api::V1::EventsController, type: :request do
  let(:organization) { create(:organization) }

  describe 'POST /events' do
    it 'returns a success' do
      post_with_token(
        organization,
        '/api/v1/events',
        event: {
          code: 'event_code',
          transaction_id: SecureRandom.uuid,
          customer_id: SecureRandom.uuid,
          timestamp: Time.zone.now.to_i,
          properties: {
            foo: 'bar',
          },
        },
      )

      expect(response).to have_http_status(:ok)
      expect(Events::CreateJob).to have_been_enqueued
    end

    context 'with missing arguments' do
      it 'returns an unprocessable entity' do
        post_with_token(
          organization,
          '/api/v1/events',
          event: { customer_id: SecureRandom.uuid },
        )

        expect(response).to have_http_status(:unprocessable_entity)

        expect(Events::CreateJob).not_to have_been_enqueued
      end
    end
  end

  describe 'POST /events/batch' do
    it 'returns a success' do
      post_with_token(
        organization,
        '/api/v1/events/batch',
        event: {
          code: 'event_code',
          transaction_id: SecureRandom.uuid,
          customer_id: SecureRandom.uuid,
          subscription_ids: %w[id1 id2],
          timestamp: Time.zone.now.to_i,
          properties: {
            foo: 'bar',
          },
        },
      )

      expect(response).to have_http_status(:ok)
      expect(Events::CreateBatchJob).to have_been_enqueued
    end

    context 'with missing arguments' do
      it 'returns an unprocessable entity' do
        post_with_token(
          organization,
          '/api/v1/events/batch',
          event: {
            code: 'event_code',
            transaction_id: SecureRandom.uuid,
            customer_id: SecureRandom.uuid,
            timestamp: Time.zone.now.to_i,
            properties: {
              foo: 'bar',
            },
          },
        )

        expect(response).to have_http_status(:unprocessable_entity)
        expect(Events::CreateBatchJob).not_to have_been_enqueued
      end
    end
  end

  describe 'GET /events/:id' do
    let(:event) { create(:event) }

    it 'returns an event' do
      get_with_token(
        event.organization,
        '/api/v1/events/' + event.transaction_id
      )

      expect(response).to have_http_status(:ok)

      api_event = JSON.parse(response.body)['event']

      %w[code transaction_id].each do |property|
        expect(api_event[property]).to eq event.attributes[property]
      end

      expect(api_event['lago_subscription_id']).to eq event.subscription_id
      expect(api_event['lago_customer_id']).to eq event.customer_id
    end

    context 'with a non-existing transaction_id' do
      it 'returns not found' do
        get_with_token(
          organization,
          '/api/v1/events/' + SecureRandom.uuid
        )

        expect(response).to have_http_status(:not_found)
      end
    end
  end
end
