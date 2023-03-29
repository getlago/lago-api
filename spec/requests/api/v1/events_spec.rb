# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Api::V1::EventsController, type: :request do
  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:) }
  let(:metric) { create(:billable_metric, organization:) }
  let(:plan) { create(:plan, organization:) }
  let(:subscription) { create(:active_subscription, customer:, organization:, plan:) }

  before { subscription }

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
    let(:subscription2) { create(:active_subscription, customer:, organization:, plan:) }

    before { subscription2 }

    it 'returns a success' do
      post_with_token(
        organization,
        '/api/v1/events/batch',
        event: {
          code: metric.code,
          transaction_id: SecureRandom.uuid,
          external_customer_id: customer.external_id,
          external_subscription_ids: [subscription.external_id, subscription2.external_id],
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

        expect(response).to have_http_status(:not_found)
        expect(Events::CreateBatchJob).not_to have_been_enqueued
      end
    end

    context 'with invalid subscription external_id' do
      it 'returns an unprocessable entity' do
        post_with_token(
          organization,
          '/api/v1/events/batch',
          event: {
            code: metric.code,
            transaction_id: SecureRandom.uuid,
            external_customer_id: customer.external_id,
            external_subscription_ids: [subscription.external_id, subscription2.external_id, 'invalid'],
            timestamp: Time.zone.now.to_i,
            properties: {
              foo: 'bar',
            },
          },
        )

        expect(response).to have_http_status(:not_found)
        expect(Events::CreateBatchJob).not_to have_been_enqueued
      end
    end
  end

  describe 'GET /events/:id' do
    let(:event) { create(:event) }

    it 'returns an event' do
      get_with_token(event.organization, "/api/v1/events/#{event.transaction_id}")

      expect(response).to have_http_status(:ok)

      %i[code transaction_id].each do |property|
        expect(json[:event][property]).to eq event.attributes[property.to_s]
      end

      expect(json[:event][:lago_subscription_id]).to eq event.subscription_id
      expect(json[:event][:lago_customer_id]).to eq event.customer_id
    end

    context 'with a non-existing transaction_id' do
      it 'returns not found' do
        get_with_token(organization, "/api/v1/events/#{SecureRandom.uuid}")

        expect(response).to have_http_status(:not_found)
      end
    end

    context 'when event is deleted' do
      it 'returns not found' do
        event.discard
        get_with_token(event.organization, "/api/v1/events/#{event.transaction_id}")

        expect(response).to have_http_status(:not_found)
      end
    end
  end

  describe 'POST /events/estimate_fees' do
    let(:charge) { create(:standard_charge, :instant, plan:, billable_metric: metric) }

    before { charge }

    it 'returns a success' do
      post_with_token(
        organization,
        '/api/v1/events/estimate_fees',
        event: {
          code: metric.code,
          external_customer_id: customer.external_id,
          properties: {
            foo: 'bar',
          },
        },
      )

      aggregate_failures do
        expect(response).to have_http_status(:success)

        expect(json[:fees].count).to eq(1)

        fee = json[:fees].first
        expect(fee[:lago_id]).to be_nil
        expect(fee[:lago_group_id]).to be_nil
        expect(fee[:item][:type]).to eq('instant_charge')
        expect(fee[:item][:code]).to eq(metric.code)
        expect(fee[:item][:name]).to eq(metric.name)
        expect(fee[:amount_cents]).to be_an(Integer)
        expect(fee[:amount_currency]).to eq('EUR')
        expect(fee[:vat_amount_cents]).to be_an(Integer)
        expect(fee[:vat_amount_currency]).to eq('EUR')
        expect(fee[:units]).to eq('1.0')
        expect(fee[:events_count]).to eq(1)
      end
    end

    context 'with missing customer id' do
      it 'returns a not found error' do
        post_with_token(
          organization,
          '/api/v1/events/estimate_fees',
          event: {
            code: metric.code,
            external_customer_id: nil,
            properties: {
              foo: 'bar',
            },
          },
        )

        aggregate_failures do
          expect(response).to have_http_status(:not_found)
        end
      end
    end

    context 'when metric code does not match an instant charge' do
      let(:charge) { create(:standard_charge, plan:, billable_metric: metric) }

      it 'returns a validation error' do
        post_with_token(
          organization,
          '/api/v1/events/estimate_fees',
          event: {
            code: metric.code,
            external_customer_id: customer.external_id,
            properties: {
              foo: 'bar',
            },
          },
        )

        aggregate_failures do
          expect(response).to have_http_status(:unprocessable_entity)
        end
      end
    end
  end
end
