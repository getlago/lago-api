# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Api::V1::EventsController, type: :request do
  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:) }
  let(:metric) { create(:billable_metric, organization:) }
  let(:plan) { create(:plan, organization:) }
  let(:subscription) { create(:subscription, customer:, organization:, plan:, started_at: 1.month.ago) }

  before { subscription }

  describe 'POST /events' do
    it 'returns a success' do
      expect do
        post_with_token(
          organization,
          '/api/v1/events',
          event: {
            code: metric.code,
            transaction_id: SecureRandom.uuid,
            external_subscription_id: subscription.external_id,
            timestamp: Time.current.to_i,
            properties: {
              foo: 'bar'
            }
          }
        )
      end.to change(Event, :count).by(1)

      expect(response).to have_http_status(:success)
      expect(json[:event][:external_subscription_id]).to eq(subscription.external_id)
    end

    context 'with duplicated transaction_id' do
      let(:event) { create(:event, organization:, external_subscription_id: subscription.external_id) }

      before { event }

      it 'returns a not found response' do
        expect do
          post_with_token(
            organization,
            '/api/v1/events',
            event: {
              code: metric.code,
              transaction_id: event.transaction_id,
              external_subscription_id: subscription.external_id,
              timestamp: Time.current.to_i,
              properties: {
                foo: 'bar'
              }
            }
          )
        end.not_to change(Event, :count)

        expect(response).to have_http_status(:unprocessable_entity)
      end
    end
  end

  describe 'POST /events/batch' do
    it 'returns a success' do
      expect do
        post_with_token(
          organization,
          '/api/v1/events/batch',
          events: [
            {
              code: metric.code,
              transaction_id: SecureRandom.uuid,
              external_subscription_id: subscription.external_id,
              timestamp: Time.current.to_i,
              properties: {
                foo: 'bar'
              }
            }
          ]
        )
      end.to change(Event, :count).by(1)

      expect(response).to have_http_status(:ok)
      expect(json[:events].first[:external_subscription_id]).to eq(subscription.external_id)
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
    let(:charge) { create(:standard_charge, :pay_in_advance, plan:, billable_metric: metric) }
    let(:tax) { create(:tax, organization:) }

    before do
      charge
      tax
    end

    it 'returns a success' do
      post_with_token(
        organization,
        '/api/v1/events/estimate_fees',
        event: {
          code: metric.code,
          external_subscription_id: subscription.external_id,
          transaction_id: SecureRandom.uuid,
          properties: {
            foo: 'bar'
          }
        }
      )

      aggregate_failures do
        expect(response).to have_http_status(:success)

        expect(json[:fees].count).to eq(1)

        fee = json[:fees].first
        expect(fee[:lago_id]).to be_nil
        expect(fee[:lago_group_id]).to be_nil
        expect(fee[:item][:type]).to eq('charge')
        expect(fee[:item][:code]).to eq(metric.code)
        expect(fee[:item][:name]).to eq(metric.name)
        expect(fee[:pay_in_advance]).to eq(true)
        expect(fee[:amount_cents]).to be_an(Integer)
        expect(fee[:amount_currency]).to eq('EUR')
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
            external_subscription_id: nil,
            properties: {
              foo: 'bar'
            }
          }
        )

        expect(response).to have_http_status(:not_found)
      end
    end

    context 'when metric code does not match an pay_in_advance charge' do
      let(:charge) { create(:standard_charge, plan:, billable_metric: metric) }

      it 'returns a validation error' do
        post_with_token(
          organization,
          '/api/v1/events/estimate_fees',
          event: {
            code: metric.code,
            external_subscription_id: subscription.external_id,
            properties: {
              foo: 'bar'
            }
          }
        )

        expect(response).to have_http_status(:unprocessable_entity)
      end
    end
  end
end
