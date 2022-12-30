# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Api::V1::EventsController, type: :request do
  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:) }
  let(:metric) { create(:billable_metric, organization:) }

  before do
    create(:active_subscription, customer:, organization:)
  end

  describe 'POST /events' do
    it 'returns a success' do
      post_with_token(
        organization,
        '/api/v1/events',
        event: {
          code: metric.code,
          transaction_id: SecureRandom.uuid,
          external_customer_id: customer.external_id,
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
      it 'returns a not found response' do
        post_with_token(
          organization,
          '/api/v1/events',
          event: { external_customer_id: customer.external_id },
        )

        expect(response).to have_http_status(:not_found)
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
          code: metric.code,
          transaction_id: SecureRandom.uuid,
          external_customer_id: customer.external_id,
          external_subscription_ids: %w[id1 id2],
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
            code: metric.code,
            transaction_id: SecureRandom.uuid,
            external_customer_id: customer.external_id,
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

      %i[code transaction_id].each do |property|
        expect(json[:event][property]).to eq event.attributes[property.to_s]
      end

      expect(json[:event][:lago_subscription_id]).to eq event.subscription_id
      expect(json[:event][:lago_customer_id]).to eq event.customer_id
    end

    context 'with a non-existing transaction_id' do
      it 'returns not found' do
        get_with_token(
          organization,
          "/api/v1/events/#{SecureRandom.uuid}",
        )

        expect(response).to have_http_status(:not_found)
      end
    end
  end
end
